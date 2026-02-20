#!/bin/bash

# Apply env-driven updates to a Lua table file
# Usage: apply_lua_vars.sh <lua_file> [ROOT_PREFIX]

set -euo pipefail

LUA_FILE="${1:-}"
ROOT_PREFIX="${2:-}"
DRY_RUN_ENV="LUA_CTRL_DRY_RUN"
STRICT_ENV="LUA_CTRL_STRICT"
CASE_SENSITIVE_ENV="LUA_CTRL_CASE_SENSITIVE"
ESC_UNDERSCORE_PLACEHOLDER="__ESC_UNDERSCORE__"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/env_name_codec.sh"
FILE_KEY="$(env_name_file_key "${LUA_FILE}" ".lua")"

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
    ${DOCS_LUA_PREFIX}*)
      raw_docs="${name#${DOCS_LUA_PREFIX}}"
      case "${raw_docs}" in
        ${FILE_KEY}__*)
          raw="${raw_docs#${FILE_KEY}__}"
          ;;
        *)
          continue
          ;;
      esac
      key="${raw//__/.}"
      full_path="${key}"
      if [ -n "${ROOT_PREFIX}" ] && [[ "${full_path}" != "${ROOT_PREFIX}" && "${full_path}" != "${ROOT_PREFIX}."* ]]; then
        full_path="${ROOT_PREFIX}.${full_path}"
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
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
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
  if (line ~ /^[ \t]*--/) {
    print line
    next
  }

  # table start: Key = {
  if (line ~ /^[ \t]*[A-Za-z0-9_]+[ \t]*=[ \t]*\{[ \t]*$/) {
    depth++
    key=line
    sub(/^[ \t]*/, "", key)
    sub(/[ \t]*=.*$/, "", key)
    stack[depth]=key
    print line
    next
  }

  # table end: }
  if (line ~ /^[ \t]*}[ \t]*,?[ \t]*$/) {
    if (depth > 0) depth--
    print line
    next
  }

  # assignment: Key = value,
  if (line ~ /^[ \t]*[A-Za-z0-9_]+[ \t]*=[ \t]*.+,?[ \t]*$/) {
    key=line
    sub(/^[ \t]*/, "", key)
    sub(/[ \t]*=.*$/, "", key)
    value=line
    sub(/^[^=]*=/, "", value)
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    comma=""
    if (value ~ /,[ \t]*$/) {
      comma=","
      sub(/,[ \t]*$/, "", value)
      sub(/[ \t]+$/, "", value)
    }
    path=join_path(key)
    if (root_prefix != "") {
      path = root_prefix "." path
    }
    path_key = (case_sensitive_enabled ? path : tolower(path))
    if (path_key in updates) {
      indent=line
      sub(/[^ \t].*$/, "", indent)
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
