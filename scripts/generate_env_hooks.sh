#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_hooks_dir="${ENV_HOOKS_DIR:-${repo_root}/scripts/env_hooks}"
entry_sh="${repo_root}/scripts/entry.sh"
sources_root="${ENV_SOURCES_DIR:-}"

source "${repo_root}/scripts/lib/env_name_codec.sh"

mkdir -p "${env_hooks_dir}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

all_envs_file="${tmp_dir}/all_envs.txt"
: > "${all_envs_file}"

add_envs() {
  while IFS= read -r name; do
    [ -z "${name}" ] && continue
    printf '%s\n' "${name}" >> "${all_envs_file}"
  done
}

if [ -f "${entry_sh}" ]; then
  refs_raw=""
  assigned_raw=""
  assigned_for_raw=""
  assigned_local_raw=""
  scan_files=()
  scan_files+=("${entry_sh}")
  if [ -d "${env_hooks_dir}" ]; then
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      scan_files+=("${file}")
    done <<< "$(find "${env_hooks_dir}" -type f -name '*.sh' | sort)"
  fi

  for file in "${scan_files[@]}"; do
    refs_raw="${refs_raw}
$(grep -oE '\$\{[A-Z][A-Z0-9_]*\}|\$[A-Z][A-Z0-9_]*' "${file}" || true)"
    assigned_raw="${assigned_raw}
$(grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]*=' "${file}" || true)"
    assigned_for_raw="${assigned_for_raw}
$(grep -oE '\bfor[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]+in\b' "${file}" || true)"
    assigned_local_raw="${assigned_local_raw}
$(grep -oE '\blocal[[:space:]]+[A-Z][A-Z0-9_]*\b' "${file}" || true)"
  done

  refs="$(printf '%s\n' "${refs_raw}" | sed -e 's/[${}]//g' | sed '/^$/d' | sort -u)"
  assigned="$(printf '%s\n' "${assigned_raw}" | sed -e 's/^[[:space:]]*//' -e 's/=.*$//' | sed '/^$/d' | sort -u)"
  assigned_for="$(printf '%s\n' "${assigned_for_raw}" | awk '{print $2}' | sed '/^$/d' | sort -u)"
  assigned_local="$(printf '%s\n' "${assigned_local_raw}" | awk '{print $2}' | sed '/^$/d' | sort -u)"
  assigned="$(printf '%s\n%s\n%s\n' "${assigned}" "${assigned_for}" "${assigned_local}" | sed '/^$/d' | sort -u)"
  handcrafted_list="$(comm -23 <(printf '%s\n' "${refs}" | sort -u) <(printf '%s\n' "${assigned}" | sort -u))"
  add_envs <<< "${handcrafted_list}"
fi

if [ -n "${sources_root}" ] && [ -d "${sources_root}" ]; then
  server_name="${SERVERNAME:-}"
  if [ -z "${server_name}" ]; then
    first_sandbox="$(find "${sources_root}" -type f -path '*Server*' -name '*_SandboxVars.lua' | sort | head -n 1)"
    if [ -n "${first_sandbox}" ]; then
      sandbox_base="$(basename "${first_sandbox}" .lua)"
      server_name="${sandbox_base%_SandboxVars}"
    fi
  fi
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    awk -v env_prefix="${env_prefix}" '
    BEGIN { section="" }
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line == "" || line ~ /^[;#]/) next
      if (match(line, /^\[([^\]]+)\]/, m)) { section=m[1]; next }
      if (match(line, /^([^=]+)=(.*)/, m)) {
        key=m[1]
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (section=="") print "INI_" key
        else print "INI_" section "__" key
      }
    }
    ' "${file}" >> "${all_envs_file}"
  done <<< "$(find "${sources_root}" -type f -path '*Server*' -name '*.ini' | sort)"

  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    base_name="$(env_name_base_from_path "${file}" ".lua")"
    file_id="$(env_name_file_id_from_base "${base_name}" "${server_name}")"
    if [ -z "${file_id}" ]; then
      env_prefix="LUA"
    else
      env_prefix="LUA_${file_id}_"
    fi
    awk '
    function encode(value,    out) {
      out=value
      gsub(/_/, "__", out)
      return out
    }
    function join_path(key,    i, path) {
      path=""
      for (i=1; i<=depth; i++) {
        if (path != "") path = path "."
        path = path stack[i]
      }
      if (path != "") path = path "." key
      else path = key
      return path
    }
    BEGIN { in_sandbox=0; depth=0 }
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line == "" || line ~ /^--/) next
      if (!in_sandbox) {
        if (line ~ /^SandboxVars[ \t]*=[ \t]*\{$/ || line ~ /^return[ \t]*\{$/) {
          in_sandbox=1
          depth=1
        }
        next
      }
      if (line ~ /^}[ \t]*,?[ \t]*$/) {
        depth--
        if (depth <= 0) { in_sandbox=0; depth=0 }
        else delete stack[depth+1]
        next
      }
      if (match(line, /^([A-Za-z0-9_]+)[ \t]*=[ \t]*\{$/, m)) {
        depth++
        stack[depth]=m[1]
        next
      }
      if (match(line, /^([A-Za-z0-9_]+)[ \t]*=[ \t]*(.+?)(,?)[ \t]*$/, m)) {
        key=m[1]
        path=join_path(key)
        n=split(path, parts, ".")
        env=env_prefix
        for (i=1; i<=n; i++) {
          env=env "_" encode(parts[i])
        }
        print env
      }
    }
    ' "${file}" >> "${all_envs_file}"
  done <<< "$(find "${sources_root}" -type f -path '*Server*' -name '*.lua' | sort)"
else
  if [ -z "${sources_root}" ]; then
    echo "Info: ENV_SOURCES_DIR not set; skipping INI/Lua env discovery." >&2
  else
    echo "Info: ENV_SOURCES_DIR not found (${sources_root}); skipping INI/Lua env discovery." >&2
  fi
fi

sort -u "${all_envs_file}" -o "${all_envs_file}"

replacement_map_key() {
  case "$1" in
    ADMINPASSWORD) echo "INI_Password" ;;
    ADMINPASSWORD_FILE) echo "INI_Password" ;;
    MOD_IDS) echo "INI_Mods" ;;
    PASSWORD) echo "INI_Password" ;;
    PASSWORD_FILE) echo "INI_Password" ;;
    RCONPASSWORD) echo "INI_RCONPassword" ;;
    RCONPASSWORD_FILE) echo "INI_RCONPassword" ;;
    WORKSHOP_IDS) echo "INI_WorkshopItems" ;;
    *) echo "" ;;
  esac
}

description_for() {
  case "$1" in
    INI_*) echo "INI override (auto-generated key)." ;;
    LUA_*) echo "Lua override (auto-generated key)." ;;
    *_FILE) echo "Read value from a file." ;;
    *) echo "TODO: describe ${1}." ;;
  esac
}

while IFS= read -r env_name; do
  [ -z "${env_name}" ] && continue
  file_path="${env_hooks_dir}/${env_name}.sh"
  if [ -f "${file_path}" ]; then
    continue
  fi
  replaces="$(replacement_map_key "${env_name}")"
  if [ -z "${replaces}" ]; then
    continue
  fi
  description="$(description_for "${env_name}")"
  {
    printf 'DESCRIPTION="%s"\n' "${description}"
    printf 'REPLACES="%s"\n' "${replaces}"
  } > "${file_path}"
done < "${all_envs_file}"

printf 'Generated env hook files in %s\n' "${env_hooks_dir}" >&2
