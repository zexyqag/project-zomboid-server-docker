#!/bin/bash

# Apply env-driven updates to an INI file
# Usage: apply_ini_vars.sh <ini_file>

set -euo pipefail

INI_FILE="${1:-}"
DRY_RUN_ENV="INI_CTRL_DRY_RUN"
STRICT_ENV="INI_CTRL_STRICT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/env_name_codec.sh"
FILE_KEY="$(env_name_file_key "${INI_FILE}" ".ini")"

if [ -z "${INI_FILE}" ] || [ ! -f "${INI_FILE}" ]; then
  echo "Error: INI file not found: ${INI_FILE}" >&2
  exit 1
fi

MAP_FILE=$(mktemp)
trap 'rm -f "$MAP_FILE"' EXIT

while IFS='=' read -r name value; do
  case "$name" in
    ${DRY_RUN_ENV}|${STRICT_ENV})
      continue
      ;;
    ${DOCS_INI_PREFIX}*)
      raw_docs="${name#${DOCS_INI_PREFIX}}"
      case "${raw_docs}" in
        ${FILE_KEY}__*)
          raw="${raw_docs#${FILE_KEY}__}"
          ;;
        *)
          continue
          ;;
      esac
      section=""
      key="$raw"
      if [[ "$raw" == *"__"* ]]; then
        section="${raw%%__*}"
        key="${raw#*__}"
      fi
      printf '%s\t%s\t%s\n' "$section" "$key" "$value" >> "$MAP_FILE"
      ;;
  esac
done < <(env)

if [ ! -s "$MAP_FILE" ]; then
  exit 0
fi

cp -f "$INI_FILE" "${INI_FILE}.bak"

DRY_RUN="${!DRY_RUN_ENV:-}"
STRICT_MODE="${!STRICT_ENV:-}"

awk -v mapfile="$MAP_FILE" -v dry_run="$DRY_RUN" -v strict_mode="$STRICT_MODE" '
BEGIN {
  FS="\t"
  while ((getline line < mapfile) > 0) {
    n=split(line, a, "\t")
    section=a[1]
    key=a[2]
    val=a[3]
    section_lc=tolower(section)
    key_lc=tolower(key)
    mapkey=section_lc SUBSEP key_lc
    updates[mapkey]=val
    key_display[mapkey]=key
    section_display[section_lc]=section
    if (keys_by_section[section_lc] != "") {
      keys_by_section[section_lc]=keys_by_section[section_lc] "\t" key_lc
    } else {
      keys_by_section[section_lc]=key_lc
    }
    updates_sections[section_lc]=1
    seen[mapkey]=0
  }
  current_section=""
  current_section_lc=""
  dry_run_enabled=(dry_run ~ /^(1|true|yes|y|on)$/)
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function flush_section(sec_lc, sec_label, emit_header,   keys, n, i, key_lc, mapkey, keyname, value, label) {
  if (flushed[sec_lc]) return
  if (!(sec_lc in keys_by_section)) return
  if (emit_header && sec_lc != "") {
    if (!dry_run_enabled) {
      print ""
      print "[" sec_label "]"
    }
  }
  n = split(keys_by_section[sec_lc], keys, "\t")
  for (i=1; i<=n; i++) {
    key_lc = keys[i]
    mapkey = sec_lc SUBSEP key_lc
    if (seen[mapkey] == 0) {
      keyname = key_display[mapkey]
      value = updates[mapkey]
      label = (sec_lc != "" ? "[" sec_label "] " : "")
      if (dry_run_enabled) {
        printf "DRY_RUN: %s%s -> %s\n", label, keyname, value > "/dev/stderr"
      } else {
        printf "APPLY: %s%s -> %s\n", label, keyname, value > "/dev/stderr"
        print keyname "=" value
      }
    }
  }
  flushed[sec_lc]=1
}
{
  line=$0
  if (line ~ /^[ \t]*[;#]/) {
    print line
    next
  }

  if (line ~ /^[ \t]*\[[^\]]+\][ \t]*$/) {
    flush_section(current_section_lc, current_section, 0)
    current_section=line
    sub(/^[ \t]*\[/, "", current_section)
    sub(/\][ \t]*$/, "", current_section)
    current_section=trim(current_section)
    current_section_lc=tolower(current_section)
    section_present[current_section_lc]=1
    print line
    next
  }

  if (line ~ /^[ \t]*[^=]+[ \t]*=.*/) {
    eq_pos=index(line, "=")
    key=substr(line, 1, eq_pos - 1)
    value=substr(line, eq_pos + 1)
    key=trim(key)
    key_lc=tolower(key)
    mapkey=current_section_lc SUBSEP key_lc
    if (mapkey in updates) {
      seen[mapkey]=1
      if (dry_run_enabled) {
        printf "DRY_RUN: %s%s -> %s\n", (current_section_lc != "" ? "[" current_section "] " : ""), key, updates[mapkey] > "/dev/stderr"
        print line
      } else {
        printf "APPLY: %s%s -> %s\n", (current_section_lc != "" ? "[" current_section "] " : ""), key, updates[mapkey] > "/dev/stderr"
        indent=line
        sub(/[^ \t].*$/, "", indent)
        print indent key "=" updates[mapkey]
      }
      next
    }
  }

  print line
}
END {
  flush_section(current_section_lc, current_section, 0)
  for (sec_lc in updates_sections) {
    if (sec_lc != "" && !(sec_lc in section_present)) {
      flush_section(sec_lc, section_display[sec_lc], 1)
    }
  }
  flush_section("", "", 0)

  unknown=0
  for (k in updates) {
    if (seen[k] == 0) {
      split(k, parts, SUBSEP)
      sec_lc=parts[1]
      key_lc=parts[2]
      keyname=key_display[k]
      seclabel=section_display[sec_lc]
      label=(sec_lc != "" ? "[" seclabel "] " : "") keyname
      printf "WARN: Unknown key %s\n", label > "/dev/stderr"
      unknown=1
    }
  }
  if (unknown == 1 && strict_mode ~ /^(1|true|yes|y|on)$/) {
    exit 3
  }
}
' "$INI_FILE" > "${INI_FILE}.tmp"

if echo "${DRY_RUN:-}" | grep -Eqi '^(1|true|yes|y|on)$'; then
  rm -f "${INI_FILE}.tmp"
else
  mv "${INI_FILE}.tmp" "$INI_FILE"
fi
