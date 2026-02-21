#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/runtime_helpers.sh"

cd ${STEAMAPPDIR}

SERVERNAME="pzserver"

ARGS=""

INI_FILE="$(resolve_ini_file)"

ENV_HOOKS_DIR="/server/scripts/custom"
if [ -d "${ENV_HOOKS_DIR}" ]; then
  declare -A hook_files
  declare -A hook_deps
  declare -A hook_replaces
  declare -A replaced_by
  declare -A hook_done

  while IFS= read -r file; do
    [ -f "${file}" ] || continue
    name="$(basename "${file}" .sh)"
    deps="$(awk -F= '$1=="DEPENDS_ON" {val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); gsub(/^"|"$|^\047|\047$/, "", val); print val; exit}' "${file}")"
    replaces="$(awk -F= '$1=="REPLACES" {val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); gsub(/^"|"$|^\047|\047$/, "", val); gsub(/[;,]/, " ", val); print val; exit}' "${file}")"
    hook_files["${name}"]="${file}"
    hook_deps["${name}"]="${deps}"
    hook_replaces["${name}"]="${replaces}"
  done <<< "$(find "${ENV_HOOKS_DIR}" -type f -path '*/hooks/*.sh' -name '*.sh' -print | sort)"

  sorted_hook_names() {
    printf '%s\n' "${!hook_files[@]}" | sed '/^$/d' | sort
  }

  while IFS= read -r hook_name; do
    [ -n "${hook_name}" ] || continue
    replaces="${hook_replaces[${hook_name}]}"
    for replaced_name in ${replaces}; do
      [ -n "${hook_files[${replaced_name}]+x}" ] || continue
      if [ -n "${replaced_by[${replaced_name}]+x}" ] && [ "${replaced_by[${replaced_name}]}" != "${hook_name}" ]; then
        echo "Warning: hook ${replaced_name} is replaced by both ${replaced_by[${replaced_name}]} and ${hook_name}; keeping ${replaced_by[${replaced_name}]}." >&2
        continue
      fi
      replaced_by["${replaced_name}"]="${hook_name}"
    done
  done <<< "$(sorted_hook_names)"

  for replaced_name in "${!replaced_by[@]}"; do
    unset "hook_files[${replaced_name}]"
    unset "hook_done[${replaced_name}]"
  done

  while IFS= read -r hook_name; do
    [ -n "${hook_name}" ] || continue
    deps="${hook_deps[${hook_name}]}"
    mapped_deps=""
    for dep in ${deps}; do
      mapped_dep="${dep}"
      if [ -n "${replaced_by[${dep}]+x}" ]; then
        mapped_dep="${replaced_by[${dep}]}"
      fi
      if [ -n "${hook_files[${mapped_dep}]+x}" ]; then
        mapped_deps="${mapped_deps} ${mapped_dep}"
      fi
    done
    hook_deps["${hook_name}"]="$(printf '%s\n' "${mapped_deps}" | xargs -n1 | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  done <<< "$(sorted_hook_names)"

  replaced_env_tokens=""
  while IFS= read -r hook_name; do
    [ -n "${hook_name}" ] || continue
    replaces="${hook_replaces[${hook_name}]}"
    for token in ${replaces}; do
      [ -n "${hook_files[${token}]+x}" ] && continue
      replaced_env_tokens="${replaced_env_tokens} ${token}"
    done
  done <<< "$(sorted_hook_names)"
  export PZ_REPLACED_ENV_TOKENS="$(printf '%s\n' "${replaced_env_tokens}" | xargs -n1 2>/dev/null | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

  run_hook() {
    local hook_name="$1"
    local hook_file="${hook_files[${hook_name}]}"
    [ -f "${hook_file}" ] || return
    . "${hook_file}"
    if type manual_apply >/dev/null 2>&1; then
      manual_apply
      unset -f manual_apply
    fi
    unset DESCRIPTION REPLACES DEPENDS_ON
  }

  while true; do
    progress=false
    while IFS= read -r hook_name; do
      [ -n "${hook_name}" ] || continue
      [ -n "${hook_done[${hook_name}]+x}" ] && continue
      deps="${hook_deps[${hook_name}]}"
      ready=true
      for dep in ${deps}; do
        if [ -z "${hook_done[${dep}]+x}" ]; then
          ready=false
          break
        fi
      done
      if [ "${ready}" = true ]; then
        run_hook "${hook_name}"
        hook_done["${hook_name}"]=1
        progress=true
      fi
    done <<< "$(sorted_hook_names)"
    if [ "${progress}" != true ]; then
      break
    fi
  done

  remaining=""
  while IFS= read -r hook_name; do
    [ -n "${hook_name}" ] || continue
    if [ -z "${hook_done[${hook_name}]+x}" ]; then
      remaining="${remaining}
${hook_name}"
    fi
  done <<< "$(sorted_hook_names)"
  if [ -n "${remaining}" ]; then
    echo "Warning: Unresolved hook dependencies; running remaining hooks in name order." >&2
    while IFS= read -r hook_name; do
      [ -z "${hook_name}" ] && continue
      run_hook "${hook_name}"
    done <<< "$(printf '%s\n' "${remaining}" | sed '/^$/d' | sort)"
  fi
fi


## Removed dedicated env var handling for Password, RCONPassword, Public, PublicName
## Use only INI_* for these keys

# Fix to a bug in start-server.sh that causes to no preload a library:
# ERROR: ld.so: object 'libjsig.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored.
export LD_LIBRARY_PATH="${STEAMAPPDIR}/jre64/lib:${LD_LIBRARY_PATH}"

## Fix the permissions in the data and workshop folders
STEAM_UID=$(id -u steam 2>/dev/null || echo 1000)
STEAM_GID=$(id -g steam 2>/dev/null || echo 1000)
chown -R "${STEAM_UID}:${STEAM_GID}" /home/steam/pz-dedicated/steamapps/workshop /home/steam/Zomboid
# When binding a host folder with Docker to the container, the resulting folder has these permissions "d---" (i.e. NO `rwx`) 
# which will cause runtime issues after launching the server.
# Fix it the adding back `rwx` permissions for the file owner (steam user)
chmod 755 /home/steam/Zomboid

su - steam -c "export LANG=${LANG} && export LD_LIBRARY_PATH=\"${STEAMAPPDIR}/jre64/lib:${LD_LIBRARY_PATH}\" && cd ${STEAMAPPDIR} && pwd && ./start-server.sh ${ARGS}"
