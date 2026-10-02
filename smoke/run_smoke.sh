#!/bin/bash
# Tests the startup scripts against fixture files and a stub server. Run: bash smoke/run_smoke.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${REPO}/scripts"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FAILED=0

fail() { echo "FAIL [${TEST}]: $*" >&2; FAILED=1; }
expect_line() {
  # $1 = file, $2 = exact line
  grep -qxF -- "$2" "$1" || fail "expected line '$2' in $(basename "$1")"
}
expect_eq() {
  [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

# Each test runs in a subshell with a fresh fake HOMEDIR/STEAMAPPDIR and no INI_/SANDBOX_ leftovers.
new_env() {
  rm -rf "${WORK:?}/home"
  export HOMEDIR="${WORK}/home" STEAMAPPDIR="${WORK}/home/pz-dedicated" SERVERNAME=pzserver
  SERVER="${HOMEDIR}/Zomboid/Server"
  mkdir -p "${SERVER}" "${STEAMAPPDIR}/media/lua/shared/Sandbox" "${HOMEDIR}/Zomboid/db"
  cp "${REPO}/smoke/fixtures/pzserver.ini" "${SERVER}/pzserver.ini"
  cp "${REPO}/smoke/fixtures/pzserver_SandboxVars.lua" "${SERVER}/pzserver_SandboxVars.lua"
  cp "${REPO}/smoke/fixtures/pzserver_spawnregions.lua" "${SERVER}/pzserver_spawnregions.lua"
  touch "${HOMEDIR}/Zomboid/db/pzserver.db"
  # shellcheck source=scripts/configure.sh
  . "${SCRIPT_DIR}/configure.sh"
}

test_ini() {
  TEST=ini
  new_env
  export INI_PublicName='My "best" server & co | $HOME \x' INI_public=true INI_NewKey=1
  apply_ini_env "${SERVER}/pzserver.ini" > /dev/null 2> "${WORK}/err"
  expect_line "${SERVER}/pzserver.ini" 'PublicName=My "best" server & co | $HOME \x'
  expect_line "${SERVER}/pzserver.ini" 'Public=true'
  expect_line "${SERVER}/pzserver.ini" 'NewKey=1'
  expect_line "${SERVER}/pzserver.ini" '# Players can hurt and kill other players'
  grep -q 'match no setting.*INI_NewKey' "${WORK}/err" || fail "unknown INI key was not reported"
  grep -q 'INI_public' "${WORK}/err" && fail "a known key in other case was reported unknown"
  (INI_Other=1 CONFIG_STRICT=true apply_ini_env "${SERVER}/pzserver.ini" > /dev/null 2>&1) && fail "CONFIG_STRICT did not stop on an unknown key"

  # On the first start the INI is empty, so nothing can be checked yet and every key is appended.
  : > "${SERVER}/pzserver.ini"
  (CONFIG_STRICT=true apply_ini_env "${SERVER}/pzserver.ini" > /dev/null 2> "${WORK}/err") || fail "first start failed in strict mode"
  expect_line "${SERVER}/pzserver.ini" 'NewKey=1'
  [ -s "${WORK}/err" ] && fail "first start reported unknown keys"
}

test_sandbox() {
  TEST=sandbox
  new_env
  export SANDBOX_Zombies=2 SANDBOX_ZombieLore__Transmission=3 SANDBOX_zombielore__mortality=7 \
    SANDBOX_Map__MapAllKnown=true SANDBOX_WorldItemRemovalList='Base.Hat, Base.Glasses' SANDBOX_Nope__Key=1
  apply_sandbox_env "${SERVER}/pzserver_SandboxVars.lua" 2> "${WORK}/err"
  local lua="${SERVER}/pzserver_SandboxVars.lua"
  expect_line "${lua}" '    Zombies = 2,'
  expect_line "${lua}" '        Transmission = 3,'
  expect_line "${lua}" '        Mortality = 7,'
  expect_line "${lua}" '        MapAllKnown = true,'
  expect_line "${lua}" '    WorldItemRemovalList = "Base.Hat, Base.Glasses",'
  expect_line "${lua}" '    -- Default = Normal'
  grep -q 'SANDBOX_Nope__Key' "${WORK}/err" || fail "unknown sandbox path was not reported"
  (CONFIG_STRICT=true apply_sandbox_env "${lua}" 2>/dev/null) && fail "CONFIG_STRICT did not stop on an unknown path"
  unset SANDBOX_Nope__Key

  rm "${lua}"
  apply_sandbox_env "${lua}" 2> "${WORK}/err"
  grep -q 'apply from the next start' "${WORK}/err" || fail "missing SandboxVars file was not reported"
}

test_preset() {
  TEST=preset
  new_env
  printf 'return {\r\n    Zombies = 4,\r\n}\r\n' > "${STEAMAPPDIR}/media/lua/shared/Sandbox/Apocalypse.lua"
  rm "${SERVER}/pzserver_SandboxVars.lua"
  SERVERPRESET=Apocalypse apply_preset "${SERVER}/pzserver_SandboxVars.lua" >/dev/null
  expect_line "${SERVER}/pzserver_SandboxVars.lua" 'SandboxVars = {'
  expect_line "${SERVER}/pzserver_SandboxVars.lua" '    Zombies = 4,'
  (SERVERPRESET=Missing apply_preset "${SERVER}/pzserver_SandboxVars.lua" 2> "${WORK}/err") && fail "a missing preset did not stop the start"
  grep -q 'Available presets: Apocalypse' "${WORK}/err" || fail "available presets were not listed"
}

make_mod() {
  # $1 = workshop item, $2 = mod folder, $3 = mod id, $4 = path of the version folder ("" for B41), $5.. = maps
  local item="$1" mod="$2" id="$3" version="$4"
  shift 4
  local base="${STEAMAPPDIR}/steamapps/workshop/content/108600/${item}/mods/${mod}"
  mkdir -p "${base}/${version}"
  printf 'name=%s\r\nid=%s\r\n' "${mod}" "${id}" > "${base}/${version}/mod.info"
  for map in "$@"; do
    mkdir -p "${base}/${version:-.}/media/maps/${map}"
    [ "${map}" = "Raven Creek" ] && touch "${base}/${version:-.}/media/maps/${map}/spawnpoints.lua"
  done
}

test_maps() {
  TEST=maps
  new_env
  make_mod 100 RavenCreek RavenCreekMod 42 "Raven Creek"
  make_mod 200 Bedford BedfordFalls "" "Bedford Falls"
  make_mod 300 Unused UnusedMod 42 "Unused Map"
  mkdir -p "${STEAMAPPDIR}/steamapps/workshop/content/108600/100/mods/RavenCreek/common/media/maps/Raven Creek Extra"
  local ini="${SERVER}/pzserver.ini"
  set_ini_value "${ini}" Mods '\RavenCreekMod;2392709985\BedfordFalls'
  set_ini_value "${ini}" Map 'Admin Map;Muldraugh, KY'
  apply_mod_maps "${ini}" "${SERVER}/pzserver_spawnregions.lua" "${STEAMAPPDIR}/steamapps/workshop/content/108600" >/dev/null
  expect_line "${ini}" 'Map=Admin Map;Raven Creek;Raven Creek Extra;Bedford Falls;Muldraugh, KY'
  expect_line "${SERVER}/pzserver_spawnregions.lua" '		{ name = "Raven Creek", file = "media/maps/Raven Creek/spawnpoints.lua" },'

  # A second start changes nothing.
  cp "${ini}" "${WORK}/ini.before"
  cp "${SERVER}/pzserver_spawnregions.lua" "${WORK}/spawn.before"
  apply_mod_maps "${ini}" "${SERVER}/pzserver_spawnregions.lua" "${STEAMAPPDIR}/steamapps/workshop/content/108600" >/dev/null
  cmp -s "${ini}" "${WORK}/ini.before" || fail "the Map line changed on the second start"
  cmp -s "${SERVER}/pzserver_spawnregions.lua" "${WORK}/spawn.before" || fail "spawnregions changed on the second start"

  expect_eq "$(merge_map_list "" "A")" "A;Muldraugh, KY"
  expect_eq "$(merge_map_list "B;Muldraugh, KY;B" "A")" "B;A;Muldraugh, KY"
}

test_workshop() {
  TEST=workshop
  new_env
  # A fake Steam API: 111 is a collection holding item 333 and collection 444 (item 555); 222 is an item.
  mkdir -p "${WORK}/bin"
  cat > "${WORK}/bin/curl" <<'CURL'
#!/bin/bash
if [[ "$*" == *"=444"* ]]; then
  echo '{"response":{"collectiondetails":[{"publishedfileid":"444","children":[{"publishedfileid":"555","filetype":0}]}]}}'
else
  echo '{"response":{"collectiondetails":[{"publishedfileid":"111","children":[{"publishedfileid":"333","filetype":0},{"publishedfileid":"444","filetype":2}]},{"publishedfileid":"222","result":9}]}}'
fi
CURL
  chmod +x "${WORK}/bin/curl"
  PATH="${WORK}/bin:${PATH}" WORKSHOP_IDS='111;222' apply_workshop_ids "${SERVER}/pzserver.ini" > /dev/null
  expect_line "${SERVER}/pzserver.ini" 'WorkshopItems=222;333;555'
  printf '#!/bin/bash\nexit 6\n' > "${WORK}/bin/curl"
  PATH="${WORK}/bin:${PATH}" WORKSHOP_IDS='111' apply_workshop_ids "${SERVER}/pzserver.ini" > /dev/null 2>&1
  expect_line "${SERVER}/pzserver.ini" 'WorkshopItems=222;333;555'
}

test_configure() {
  TEST=configure
  new_env
  echo 'rcon from file' > "${WORK}/rcon"
  export INI_Password='p&ss|word' INI_RCONPassword=ignored INI_RCONPassword_FILE="${WORK}/rcon" ADMINPASSWORD='p@ss word$USER' \
    MEMORY=2048m DEBUG=true ADMINUSERNAME=boss PORT=17000 STEAMVAC=TRUE WORKSHOP_IDS=""
  configure_server > /dev/null 2>&1
  expect_line "${SERVER}/pzserver.ini" 'Password=p&ss|word'
  expect_line "${SERVER}/pzserver.ini" 'RCONPassword=rcon from file'
  expect_line "${SERVER}/pzserver.ini" 'WorkshopItems='
  expect_eq "$(printf '%q ' "${ARGS[@]}")" "-Xms2048m -Xmx2048m -- -debug -adminusername boss -servername pzserver -port 17000 -steamvac true "

  # Without the database the admin password is passed, and required.
  rm "${HOMEDIR}/Zomboid/db/pzserver.db"
  configure_server > /dev/null 2>&1
  expect_eq "${ARGS[*]: -2}" "-adminpassword p@ss word\$USER"
  unset ADMINPASSWORD
  (configure_server > /dev/null 2> "${WORK}/err") && fail "the first start went ahead without ADMINPASSWORD"
  grep -q 'ADMINPASSWORD' "${WORK}/err" || fail "the missing ADMINPASSWORD was not explained"
}

test_list_env() {
  TEST=list-env
  new_env
  export ADMINPASSWORD=secret
  set_ini_value "${SERVER}/pzserver.ini" Password hunter2
  bash "${SCRIPT_DIR}/list_env.sh" > "${WORK}/out"
  expect_line "${WORK}/out" '# Players can hurt and kill other players'
  expect_line "${WORK}/out" 'INI_PVP=true'
  expect_line "${WORK}/out" 'SANDBOX_ZombieLore__Transmission=1'
  expect_line "${WORK}/out" 'ADMINPASSWORD=(set)'
  expect_line "${WORK}/out" 'INI_Password=(set)'
  expect_line "${WORK}/out" '## Sandbox settings (pzserver_SandboxVars.lua)'
  bash "${SCRIPT_DIR}/list_env.sh" zombielore > "${WORK}/out"
  grep -q '^INI_' "${WORK}/out" && fail "the filter kept unrelated rows"
  grep -q '^SANDBOX_ZombieLore__Mortality=' "${WORK}/out" || fail "the filter dropped matching rows"
  bash "${SCRIPT_DIR}/list_env.sh" --tsv > "${WORK}/out"
  expect_line "${WORK}/out" "$(printf 'sandbox\tSANDBOX_ZombieLore__Mortality\t5\tDefault = Instant')"
}

test_vars_documented() {
  TEST=vars
  local name
  while IFS=$'\t' read -r name _; do
    grep -rq --include='*.sh' -- "${name}" "${SCRIPT_DIR}" || fail "${name} is documented but never read"
  done < "${SCRIPT_DIR}/vars.tsv"
  for name in $(grep -rhoE '\$\{[A-Z][A-Z0-9_]+(:-|\+x|\})' "${SCRIPT_DIR}" | grep -oE '[A-Z][A-Z0-9_]+' | sort -u); do
    case "${name}" in
      HOMEDIR|STEAMAPPDIR|SERVERNAME|SCRIPT_DIR|LD_LIBRARY_PATH|SERVER_*|SHUTDOWN_*|CONSOLE_FD|ARGS|VANILLA_MAP|KEY|VALUE|NAME) continue ;;
    esac
    grep -q "^${name}	" "${SCRIPT_DIR}/vars.tsv" || fail "${name} is read but not in vars.tsv"
  done
}

test_entry() {
  TEST=entry
  new_env
  cat > "${STEAMAPPDIR}/start-server.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "${HOMEDIR}/args"
echo "LOG  : Network      f:0> *** SERVER STARTED ****"
while IFS= read -r line; do
  [ "${line}" = quit ] && { echo "saving"; exit 0; }
  echo "command: ${line}"
done
EOF
  chmod +x "${STEAMAPPDIR}/start-server.sh"
  (cd "${WORK}" && exec bash "${SCRIPT_DIR}/entry.sh") > "${WORK}/entry.log" 2>&1 &
  local pid=$! healthy=false
  for _ in $(seq 1 50); do
    bash "${SCRIPT_DIR}/healthcheck.sh" && { healthy=true; break; }
    sleep 0.1
  done
  [ "${healthy}" = true ] || { fail "the health check never passed"; cat "${WORK}/entry.log" >&2; }
  bash "${SCRIPT_DIR}/console.sh" servermsg "hello there" > /dev/null || fail "console failed"
  sleep 0.2
  grep -qxF 'command: servermsg "hello there"' "${WORK}/entry.log" || fail "console command did not reach the server"
  kill -TERM "${pid}"
  wait "${pid}"
  expect_eq "$?" 0
  grep -q saving "${WORK}/entry.log" || fail "the server did not receive quit"
  bash "${SCRIPT_DIR}/healthcheck.sh" && fail "the health check passed after the server stopped"
  expect_line "${HOMEDIR}/args" "-servername"
}

for t in test_ini test_sandbox test_preset test_maps test_workshop test_configure test_list_env test_vars_documented test_entry; do
  ( "${t}"; exit "${FAILED}" ) || FAILED=1
done

if [ "${FAILED}" -ne 0 ]; then
  echo "Smoke tests failed" >&2
  exit 1
fi
echo "Smoke tests passed"
