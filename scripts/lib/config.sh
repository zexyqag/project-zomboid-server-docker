#!/bin/bash
# Edits the server's INI and SandboxVars files from environment variables.

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

read_secret() {
  # $1 = variable holding the value, $2 = variable naming a file that holds it (preferred)
  local value_var="$1" file_var="$2"
  local file_path="${!file_var:-}"
  if [ -n "${file_path}" ]; then
    if [ -f "${file_path}" ]; then
      printf '%s' "$(<"${file_path}")"
      return
    fi
    echo "Warning: ${file_var} is set but the file does not exist: ${file_path}" >&2
  fi
  printf '%s' "${!value_var:-}"
}

ini_value() {
  # $1 = INI file, $2 = key; prints the value, empty when the key is missing
  KEY="$2" awk '
    BEGIN { k = tolower(ENVIRON["KEY"]) }
    { i = index($0, "=") }
    i > 1 && tolower(substr($0, 1, i - 1)) == k { print substr($0, i + 1); exit }
  ' "$1"
}

set_ini_value() {
  # $1 = INI file, $2 = key, $3 = value; replaces the key (case-insensitive) or appends it
  KEY="$2" VALUE="$3" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
    { i = index($0, "=") }
    !found && i > 1 && tolower(substr($0, 1, i - 1)) == tolower(k) {
      print substr($0, 1, i - 1) "=" v
      found = 1
      next
    }
    { print }
    END { if (!found) print k "=" v }
  ' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

# Applies every INI_<Key> variable to the INI file. INI_<Key>_FILE reads the value from a file
# (for Docker secrets) and wins over INI_<Key>. Keys missing from a non-empty file are appended
# with a warning, because the server ignores unknown keys and a typo would otherwise go unnoticed.
apply_ini_env() {
  local ini_file="$1" name key value check_unknown=true unknown=""
  [ -s "${ini_file}" ] || check_unknown=false
  while IFS= read -r name; do
    key="${name#INI_}"
    key="${key%_FILE}"
    if [[ "${name}" == *_FILE ]]; then
      [ -f "${!name}" ] || { echo "Warning: ${name} is set but the file does not exist: ${!name}" >&2; continue; }
      value="$(<"${!name}")"
    elif [ -n "$(printenv "${name}_FILE")" ]; then
      continue
    else
      value="${!name}"
    fi
    if [ "${check_unknown}" = true ] && ! grep -qi "^${key}=" "${ini_file}"; then
      unknown="${unknown} ${name}"
    fi
    set_ini_value "${ini_file}" "${key}" "${value}"
    echo "Config: ${key} set from ${name}"
  done < <(compgen -e | grep '^INI_' | sort)
  report_unknown "${unknown}" "${ini_file}"
}

# Applies every SANDBOX_<Group>__<Key> variable to the SandboxVars file. Values replace the
# existing ones as Lua literals; a string setting keeps its quotes when the value has none.
apply_sandbox_env() {
  local lua_file="$1" name path names updates unknown
  names="$(compgen -e | grep '^SANDBOX_' | sort || true)"
  [ -n "${names}" ] || return 0
  if [ ! -f "${lua_file}" ]; then
    echo "Warning: ${lua_file} does not exist yet, so SANDBOX_ settings apply from the next start (or set SERVERPRESET to create it now)." >&2
    return 0
  fi
  updates="$(mktemp)"
  while IFS= read -r name; do
    path="${name#SANDBOX_}"
    printf '%s\t%s\t%s\n' "${name}" "${path//__/.}" "${!name}" >> "${updates}"
  done <<< "${names}"
  unknown="$(awk -v updates_file="${updates}" -v out="${lua_file}.tmp" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    BEGIN {
      while ((getline line < updates_file) > 0) {
        split(line, f, "\t")
        k = tolower(f[2])
        env_of[k] = f[1]
        path_of[k] = f[2]
        value_of[k] = substr(line, length(f[1]) + length(f[2]) + 3)
      }
    }
    {
      line = $0
      code = trim(line)
      if (code ~ /^[A-Za-z0-9_]+[ \t]*=[ \t]*\{[ \t]*$/) {
        key = code
        sub(/[ \t]*=.*/, "", key)
        if (seen_root) stack[++depth] = key
        seen_root = 1
        print line > out
        next
      }
      if (code ~ /^\}[ \t]*,?$/) {
        if (depth > 0) depth--
        print line > out
        next
      }
      if (code ~ /^[A-Za-z0-9_]+[ \t]*=/) {
        key = code
        sub(/[ \t]*=.*/, "", key)
        path = ""
        for (i = 1; i <= depth; i++) path = path stack[i] "."
        path = tolower(path key)
        if (path in value_of) {
          old = code
          sub(/^[^=]*=[ \t]*/, "", old)
          sub(/[ \t]*,?[ \t]*$/, "", old)
          new = value_of[path]
          if (old ~ /^".*"$/ && new !~ /^".*"$/) {
            gsub(/\\/, "\\\\", new)
            gsub(/"/, "\\\"", new)
            new = "\"" new "\""
          }
          indent = line
          sub(/[^ \t].*$/, "", indent)
          print indent key " = " new "," > out
          printf "Config: sandbox %s set from %s\n", path_of[path], env_of[path] > "/dev/stderr"
          applied[path] = 1
          next
        }
      }
      print line > out
    }
    END { for (k in env_of) if (!(k in applied)) printf " %s", env_of[k] }
  ' "${lua_file}")"
  rm -f "${updates}"
  mv "${lua_file}.tmp" "${lua_file}"
  report_unknown "${unknown}" "${lua_file}"
}

report_unknown() {
  # $1 = space-separated variable names that matched no setting, $2 = file
  [ -n "${1// /}" ] || return 0
  echo "Warning: these variables match no setting in $2:$1" >&2
  echo "         Run 'docker exec <container> list-env' to see the valid names." >&2
  if is_true "${CONFIG_STRICT:-}"; then
    echo "Error: CONFIG_STRICT is set, refusing to start with unknown settings." >&2
    exit 1
  fi
}
