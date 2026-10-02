#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/runtime_helpers.sh"
. "${SCRIPT_DIR}/lib/hooks.sh"

cd "${STEAMAPPDIR}" || exit 1

SERVERNAME="pzserver"

ARGS=()

INI_FILE="$(resolve_ini_file)"

run_env_hooks "${SCRIPT_DIR}/custom"

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

# runuser execs the command without a shell, so each ARGS element reaches the server as one argument.
export LANG
exec runuser -u steam -- ./start-server.sh "${ARGS[@]}"
