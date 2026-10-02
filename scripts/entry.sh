#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/runtime_helpers.sh"
. "${SCRIPT_DIR}/lib/hooks.sh"

cd "${STEAMAPPDIR}" || exit 1

SERVERNAME="pzserver"

ARGS=()

# The server keeps the values in an existing INI and fills in the rest, so creating it lets the
# hooks apply settings on the very first start.
INI_FILE="${HOMEDIR}/Zomboid/Server/${SERVERNAME}.ini"
mkdir -p "$(dirname "${INI_FILE}")"
[ -f "${INI_FILE}" ] || touch "${INI_FILE}"

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

# The server saves the world on the console command `quit`. Docker only signals PID 1, so stdin is a
# FIFO held open here and SIGTERM/SIGINT write `quit` into it instead of killing the JVM.
SERVER_CONSOLE="/tmp/pz-console"
rm -f "${SERVER_CONSOLE}"
mkfifo "${SERVER_CONSOLE}"
exec {CONSOLE_FD}<>"${SERVER_CONSOLE}"

shutdown_server() {
  [ -n "${SHUTDOWN_STARTED:-}" ] && return
  SHUTDOWN_STARTED=1
  echo "*** INFO: Shutdown signal received, sending 'quit' to save the world ***"
  printf 'quit\n' >&"${CONSOLE_FD}"
  # A further signal interrupts wait with 128+n while the server is still saving.
  while true; do
    wait "${SERVER_PID}"
    SHUTDOWN_EXIT=$?
    if [ "${SHUTDOWN_EXIT}" -le 128 ] || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
      break
    fi
  done
  echo "*** INFO: Server stopped with exit code ${SHUTDOWN_EXIT} ***"
}

# runuser execs the command without a shell, so each ARGS element reaches the server as one argument.
export LANG
runuser -u steam -- ./start-server.sh "${ARGS[@]}" <"${SERVER_CONSOLE}" &
SERVER_PID=$!
trap shutdown_server TERM INT

wait "${SERVER_PID}"
SERVER_EXIT=$?
if [ -n "${SHUTDOWN_STARTED:-}" ]; then
  SERVER_EXIT="${SHUTDOWN_EXIT}"
fi
rm -f "${SERVER_CONSOLE}"
exit "${SERVER_EXIT}"
