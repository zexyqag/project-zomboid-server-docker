#!/bin/bash

safe_update_ini_key() {
  # $1 = INI file path
  # $2 = INI key (e.g., Password, RCONPassword)
  # $3 = value variable name (env var or file)
  # $4 = optional: file variable name (e.g., PASSWORD_FILE)
  local ini_file="$1"
  local key="$2"
  local value_var="$3"
  local file_var="$4"
  local value=""

  # Prefer file if provided and exists
  if [ -n "$file_var" ]; then
    local file_path="${!file_var}"
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
      value=$(<"$file_path")
    fi
  fi
  # Fallback to env var if value still empty
  if [ -z "$value" ] && [ -n "${!value_var}" ]; then
    value="${!value_var}"
  fi

  if [ -n "$value" ] && [ -f "$ini_file" ]; then
    local current_val
    current_val=$(awk -F '=' -v k="$key" '$1 ~ "^"k"[ \t]*$" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$ini_file")
    if [ "$current_val" != "$value" ]; then
      echo "*** INFO: $key has changed, updating INI file directly ***"
      export "INI_${key}=${value}"
    fi
  fi
}

resolve_ini_file() {
  local server_dir="${HOMEDIR}/Zomboid/Server"
  local default_path="${server_dir}/${SERVERNAME}.ini"
  if [ -f "${default_path}" ]; then
    echo "${default_path}"
    return
  fi
  shopt -s nullglob
  local files=("${server_dir}"/*.ini)
  shopt -u nullglob
  if [ ${#files[@]} -eq 1 ]; then
    echo "${files[0]}"
  else
    echo "${default_path}"
  fi
}

resolve_sandboxvars_file() {
  local server_dir="${HOMEDIR}/Zomboid/Server"
  local default_path="${server_dir}/${SERVERNAME}_SandboxVars.lua"
  if [ -f "${default_path}" ]; then
    echo "${default_path}"
    return
  fi
  shopt -s nullglob
  local files=("${server_dir}"/*_SandboxVars.lua)
  shopt -u nullglob
  if [ ${#files[@]} -eq 1 ]; then
    echo "${files[0]}"
  else
    echo "${default_path}"
  fi
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

set_ini_override() {
  # $1 = key, $2 = value
  local key="$1"
  local value="$2"
  local env_name="INI_${key}"
  # List of keys managed by extra logic
  case "$key" in
    WorkshopItems|Mods|Map|AntiCheatProtectionType*|Password|RCONPassword)
      if [ -n "${!env_name+x}" ]; then
        case "$key" in
          Password)
            msg="Use PASSWORD or PASSWORD_FILE environment variables instead."
            ;;
          RCONPassword)
            msg="Use RCONPASSWORD or RCONPASSWORD_FILE environment variables instead."
            ;;
          *)
            msg="This key is managed by entry.sh logic."
            ;;
        esac
        echo "ERROR: Do not set INI_${key}. $msg Remove INI_${key} from your environment to avoid breaking server setup." >&2
        exit 10
      fi
      ;;
    *)
      export "${env_name}=${value}"
      ;;
  esac
}
