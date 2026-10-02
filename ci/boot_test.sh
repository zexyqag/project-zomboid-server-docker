#!/bin/bash
# Boots a freshly built image and checks that the server starts, keeps settings written before
# its first start, creates its database and saves on `docker stop`, then starts it again to check
# the settings against the files the server wrote. Writes the env reference for the docs site from
# the running server.
# Usage: boot_test.sh <image> <reference.json> <image tag shown on the site>

set -euo pipefail

image="$1"
reference="$2"
label="$3"
name="pz-boot-test"
home="/home/steam/Zomboid"

fail() {
  echo "Error: $*" >&2
  docker logs --tail 300 "${name}" >&2 || true
  exit 1
}
trap 'docker rm -f "${name}" >/dev/null 2>&1 || true' EXIT

wait_healthy() {
  local status=""
  echo "Waiting for the server to start"
  for _ in $(seq 1 240); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "${name}")"
    [ "${status}" = healthy ] && return 0
    [ "$(docker inspect -f '{{.State.Running}}' "${name}")" = true ] || fail "the server exited before it started"
    sleep 5
  done
  fail "the server did not start within 20 minutes"
}

stop_server() {
  # $1 = how many clean stops the log should show by now
  echo "Stopping the server"
  docker stop -t 120 "${name}" >/dev/null
  exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${name}")"
  [ "${exit_code}" = 0 ] || fail "the server exited with ${exit_code} on docker stop instead of saving and exiting cleanly"
  [ "$(docker logs "${name}" 2>&1 | grep -c "Server stopped with exit code 0")" = "$1" ] || fail "the shutdown did not go through quit"
}

# SANDBOX_ only applies once the server has written SandboxVars, so it's checked on the second start.
docker run -d --name "${name}" --health-interval=5s \
  -e ADMINPASSWORD=boot-test -e INI_PublicName="Boot test" -e INI_Public=false \
  -e SANDBOX_ZombieLore__Transmission=4 -e CONFIG_STRICT=true \
  "${image}" >/dev/null
wait_healthy

docker exec "${name}" grep -qx 'PublicName=Boot test' "${home}/Server/pzserver.ini" \
  || fail "INI_PublicName written before the first start was not kept"
docker exec "${name}" test -f "${home}/db/pzserver.db" \
  || fail "no database at Zomboid/db/pzserver.db; configure.sh uses it to tell the first start apart"
docker exec "${name}" test -s "${home}/Server/pzserver_SandboxVars.lua" \
  || fail "the server did not write pzserver_SandboxVars.lua"

# INI_ and SANDBOX_ cover these two files; a new settings file from the game needs its own prefix.
others="$(docker exec "${name}" find "${home}/Server" -maxdepth 1 -type f ! -name pzserver.ini ! -name pzserver_SandboxVars.lua ! -name pzserver_spawnregions.lua ! -name pzserver_spawnpoints.lua ! -name '*.bak' -printf '%f ')"
[ -z "${others}" ] || echo "::warning title=New server files::No env vars cover ${others}"

rows="$(docker exec "${name}" list-env --tsv)"
for kind in image ini sandbox; do
  grep -q "^${kind}	" <<< "${rows}" || fail "list-env found no ${kind} settings"
done
# Nested sandbox tables are joined with "__", so a key containing "__" could collide with a path.
duplicates="$(cut -f2 <<< "${rows}" | sort | uniq -d)"
[ -z "${duplicates}" ] || fail "list-env produced duplicate names: ${duplicates}"
mkdir -p "$(dirname "${reference}")"
jq -R -s --arg tag "${label}" '
  split("\n")
  | map(select(length > 0) | split("\t") | {kind: .[0], name: .[1], description: (.[3] // "")})
  | {image_tag: $tag, vars: .}
' <<< "${rows}" > "${reference}"

stop_server 1

# CONFIG_STRICT now checks every variable against the server's own files.
docker start "${name}" >/dev/null
wait_healthy
docker exec "${name}" grep -qx 'PublicName=Boot test' "${home}/Server/pzserver.ini" \
  || fail "PublicName did not survive a restart"
docker exec "${name}" grep -qE '^[[:space:]]*Transmission = 4,' "${home}/Server/pzserver_SandboxVars.lua" \
  || fail "SANDBOX_ZombieLore__Transmission was not applied on the second start"
# Once the database exists the admin password must stay out of the command line.
docker exec "${name}" sh -c 'cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\0" " "' | grep -q -- '-adminpassword' \
  && fail "-adminpassword was passed although the database exists"
stop_server 2
echo "Boot test passed"
