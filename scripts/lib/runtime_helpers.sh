#!/bin/bash

read_secret() {
  # $1 = value variable name, $2 = variable naming a file that holds the value (preferred)
  local value_var="$1"
  local file_var="$2"
  local file_path="${!file_var:-}"
  if [ -n "${file_path}" ]; then
    if [ -f "${file_path}" ]; then
      printf '%s' "$(<"${file_path}")"
      return
    fi
    echo "Warning: ${file_var} is set but file not found: ${file_path}" >&2
  fi
  printf '%s' "${!value_var:-}"
}

set_ini_value() {
  # $1 = key, $2 = value; replaces the key in INI_FILE or appends it
  KEY="$1" VALUE="$2" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "${INI_FILE}" > "${INI_FILE}.tmp"
  mv "${INI_FILE}.tmp" "${INI_FILE}"
}

is_true() {
  # $1 = value to check
  # $2 = default (optional, "false" if not set)
  local val="${1,,}"
  local default="${2:-false}"
  case "$val" in
    1|true|yes|y|on) return 0 ;;
    0|false|no|n|off) return 1 ;;
    *)
      case "${default,,}" in
        1|true|yes|y|on) return 0 ;;
        *) return 1 ;;
      esac
    ;;
  esac
}
