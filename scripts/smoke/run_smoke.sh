#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

run_ini_dry_run() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export INIVARS_Public=true
    export INIVARS_PublicName="New Name"
    export INIVARS_Mods="ModA"
    export INIVARS_ServerOptions__PVP=false
    export INIVARS_ServerOptions__DropOffWhiteList=false
    export INIVARS_CTRL_DRY_RUN=true
    "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini" "INIVARS_"
  )
  if ! diff -u "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini" >/dev/null; then
    echo "INI dry-run modified file" >&2
    exit 1
  fi
}

run_ini_apply() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export INIVARS_Public=true
    export INIVARS_PublicName="New Name"
    export INIVARS_Mods="ModA"
    export INIVARS_ServerOptions__PVP=false
    export INIVARS_ServerOptions__DropOffWhiteList=false
    "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini" "INIVARS_"
  )
  diff -u "${SCRIPT_DIR}/expected.ini" "${TMP_DIR}/sample.ini" >/dev/null
}

run_lua_dry_run() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export SANDBOXVARS_ZombieLore_Transmission=4
    export SANDBOXVARS_World__Event=2
    export SANDBOXVARS_CTRL_DRY_RUN=true
    "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "SANDBOXVARS_"
  )
  if ! diff -u "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua" >/dev/null; then
    echo "Lua dry-run modified file" >&2
    exit 1
  fi
}

run_lua_apply() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export SANDBOXVARS_ZombieLore_Transmission=4
    export SANDBOXVARS_World__Event=2
    "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "SANDBOXVARS_"
  )
  diff -u "${SCRIPT_DIR}/expected_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua" >/dev/null
}

echo "Running INI helper smoke tests..."
run_ini_dry_run
echo "INI dry-run ok"
run_ini_apply
echo "INI apply ok"

echo "Running Lua helper smoke tests..."
run_lua_dry_run
echo "Lua dry-run ok"
run_lua_apply
echo "Lua apply ok"

echo "Smoke tests passed."
