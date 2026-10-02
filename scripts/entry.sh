#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERNAME="pzserver"
SERVER_CONSOLE="/tmp/pz-console"
SERVER_READY="/tmp/pz-ready"
SERVER_PID_FILE="/tmp/pz-server.pid"

# shellcheck source=scripts/configure.sh
. "${SCRIPT_DIR}/configure.sh"

if [ ! -w "${HOMEDIR}/Zomboid" ]; then
  echo "Error: ${HOMEDIR}/Zomboid is not writable by $(id -un) (uid $(id -u)). For a bind mount, run: chown -R $(id -u):$(id -g) <host folder>" >&2
  exit 1
fi

cd "${STEAMAPPDIR}" || exit 1
configure_server

# start-server.sh preloads libjsig.so, which is only found through this path.
export LD_LIBRARY_PATH="${STEAMAPPDIR}/jre64/lib:${LD_LIBRARY_PATH:-}"
export LANG

echo "Server ports: ${PORT:-16261}/udp and ${UDPPORT:-16262}/udp"

# The server saves the world on the console command `quit`. Docker only signals PID 1, so stdin is a
# FIFO held open here and SIGTERM/SIGINT write `quit` into it instead of killing the JVM.
rm -f "${SERVER_CONSOLE}" "${SERVER_READY}"
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

# Output passes through this loop, which marks the server ready for the health check once it has started.
./start-server.sh "${ARGS[@]}" <"${SERVER_CONSOLE}" > >(
  trap '' TERM INT
  while IFS= read -r line || [ -n "${line}" ]; do
    printf '%s\n' "${line}"
    if [[ "${line}" == *"*** SERVER STARTED ***"* ]]; then
      : > "${SERVER_READY}"
    fi
  done
) 2>&1 &
SERVER_PID=$!
echo "${SERVER_PID}" > "${SERVER_PID_FILE}"
trap shutdown_server TERM INT

wait "${SERVER_PID}"
SERVER_EXIT=$?
if [ -n "${SHUTDOWN_STARTED:-}" ]; then
  SERVER_EXIT="${SHUTDOWN_EXIT}"
fi
rm -f "${SERVER_CONSOLE}" "${SERVER_READY}" "${SERVER_PID_FILE}"
exit "${SERVER_EXIT}"
