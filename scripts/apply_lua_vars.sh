#!/bin/bash

# Apply env-driven updates to a Lua table file
# Usage: apply_lua_vars.sh <lua_file> [ENV_PREFIX] [ROOT_PREFIX]

set -euo pipefail

LUA_FILE="${1:-}"
ENV_PREFIX="${2:-LUA_}"
ROOT_PREFIX="${3:-}"
DRY_RUN_ENV="LUA_CTRL_DRY_RUN"
STRICT_ENV="LUA_CTRL_STRICT"
CASE_SENSITIVE_ENV="LUA_CTRL_CASE_SENSITIVE"
ESC_UNDERSCORE_PLACEHOLDER="__ESC_UNDERSCORE__"

if [ -z "${LUA_FILE}" ] || [ ! -f "${LUA_FILE}" ]; then
  echo "Error: Lua file not found: ${LUA_FILE}" >&2
  exit 1
fi

# Build a temp map of updates from env vars
MAP_FILE=$(mktemp)
trap 'rm -f "$MAP_FILE"' EXIT

while IFS='=' read -r name value; do
  case "$name" in
    ${DRY_RUN_ENV}|${STRICT_ENV}|${CASE_SENSITIVE_ENV})
      continue
      ;;
    ${ENV_PREFIX}*)
      key="${name#${ENV_PREFIX}}"
      # _ is a path separator, __ is a literal underscore
      key_placeholder="${key//__/${ESC_UNDERSCORE_PLACEHOLDER}}"
      key_placeholder="${key_placeholder//_/.}"
      key="${key_placeholder//${ESC_UNDERSCORE_PLACEHOLDER}/_}"
      # Build full path under the root table (if provided)
      if [ -n "${ROOT_PREFIX}" ]; then
        full_path="${ROOT_PREFIX}.${key}"
      else
        full_path="${key}"
      fi
      printf '%s=%s\n' "${full_path}" "$value" >> "$MAP_FILE"
      ;;
  esac
done < <(env)

if [ ! -s "$MAP_FILE" ]; then
  exit 0
fi

# Backup before editing
cp -f "$LUA_FILE" "${LUA_FILE}.bak"

DRY_RUN="${!DRY_RUN_ENV:-}"
STRICT_MODE="${!STRICT_ENV:-}"
CASE_SENSITIVE="${!CASE_SENSITIVE_ENV:-}"

awk -v mapfile="$MAP_FILE" -v dry_run="$DRY_RUN" -v strict_mode="$STRICT_MODE" -v case_sensitive="$CASE_SENSITIVE" -v root_prefix="$ROOT_PREFIX" '
BEGIN {
  case_sensitive_enabled=(case_sensitive ~ /^(1|true|yes|y|on)$/)
  root_prefix_lc=tolower(root_prefix)
  while ((getline line < mapfile) > 0) {
    split(line, a, "=")
    key=a[1]
    val=substr(line, index(line, "=")+1)
    map_key = (case_sensitive_enabled ? key : tolower(key))
    updates[map_key]=val
    seen[map_key]=0
  }
  depth=0
}
function trim(s) { sub(/^\s+/, "", s); sub(/\s+$/, "", s); return s }
function join_path(k,   i, start, path) {
  path=""
  start=1
  if (root_prefix != "" && depth > 0) {
    if (tolower(stack[1]) == root_prefix_lc) {
      start=2
    }
  }
  for (i=start; i<=depth; i++) {
    if (path != "") path = path "."
    path = path stack[i]
  }
  if (path != "") path = path "." k
  else path = k
  return path
}
{
  line=$0
  # skip comment-only lines
  if (line ~ /^\s*--/) {
    print line
    next
  }

  # table start: Key = {
  if (match(line, /^\s*([A-Za-z0-9_]+)\s*=\s*\{\s*$/, m)) {
    depth++
    stack[depth]=m[1]
    print line
    next
  }

  # table end: }
  if (match(line, /^\s*}\s*,?\s*$/)) {
    if (depth > 0) depth--
    print line
    next
  }

  # assignment: Key = value,
  if (match(line, /^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)(,?)\s*$/, m)) {
    key=m[1]
    value=m[2]
    comma=m[3]
    path=join_path(key)
    if (root_prefix != "") {
      path = root_prefix "." path
    }
    path_key = (case_sensitive_enabled ? path : tolower(path))
    if (path_key in updates) {
      indent=""
      match(line, /^\s*/, ind)
      indent=substr(line, RSTART, RLENGTH)
      newval=updates[path_key]
      seen[path_key]=1
      if (dry_run ~ /^(1|true|yes|y|on)$/) {
        printf "DRY_RUN: %s -> %s\n", path, newval > "/dev/stderr"
        print line
      } else {
        printf "APPLY: %s -> %s\n", path, newval > "/dev/stderr"
        print indent key " = " newval comma
      }
      next
    }
  }

  print line
}
END {
  unknown=0
  for (k in updates) {
    if (seen[k] == 0) {
      printf "WARN: Unknown key %s\n", k > "/dev/stderr"
      unknown=1
    }
  }
  if (unknown == 1 && strict_mode ~ /^(1|true|yes|y|on)$/) {
    exit 3
  }
}
' "$LUA_FILE" > "${LUA_FILE}.tmp"

if echo "${DRY_RUN:-}" | grep -Eqi '^(1|true|yes|y|on)$'; then
  rm -f "${LUA_FILE}.tmp"
else
  mv "${LUA_FILE}.tmp" "$LUA_FILE"
fi
