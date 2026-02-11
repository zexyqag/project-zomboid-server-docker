#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/runtime_helpers.sh"

cd ${STEAMAPPDIR}

SERVERNAME="pzserver"

ARGS=""

INI_FILE="$(resolve_ini_file)"

ENV_HOOKS_DIR="/server/scripts/env_hooks"
if [ -d "${ENV_HOOKS_DIR}" ]; then
  declare -A hook_files
  declare -A hook_deps
  declare -A hook_done

  while IFS= read -r file; do
    [ -f "${file}" ] || continue
    name="$(basename "${file}" .sh)"
    deps="$(awk -F= '$1=="DEPENDS_ON" {val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); gsub(/^"|"$|^\047|\047$/, "", val); print val; exit}' "${file}")"
    hook_files["${name}"]="${file}"
    hook_deps["${name}"]="${deps}"
  done <<< "$(find "${ENV_HOOKS_DIR}" -type f -name '*.sh' | sort)"

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
    for hook_name in "${!hook_files[@]}"; do
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
    done
    if [ "${progress}" != true ]; then
      break
    fi
  done

  remaining=""
  for hook_name in "${!hook_files[@]}"; do
    if [ -z "${hook_done[${hook_name}]+x}" ]; then
      remaining="${remaining}
${hook_name}"
    fi
  done
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
