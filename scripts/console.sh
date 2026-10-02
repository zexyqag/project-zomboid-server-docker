#!/bin/bash
# Sends a command to the running server's console, e.g. `console save` or `console servermsg "Restart in 5 minutes"`.
# The server's reply appears in the container log.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: console <server command>, e.g. console players" >&2
  exit 2
fi
if [ ! -p /tmp/pz-console ] || [ ! -f /tmp/pz-ready ]; then
  echo "Error: the server is not running yet." >&2
  exit 1
fi
# Arguments with spaces are quoted, as the server expects for messages and names.
command=""
for arg in "$@"; do
  [[ "${arg}" == *" "* ]] && arg="\"${arg}\""
  command="${command:+${command} }${arg}"
done
printf '%s\n' "${command}" > /tmp/pz-console
echo "Sent: ${command}  (the reply is in docker logs)"
