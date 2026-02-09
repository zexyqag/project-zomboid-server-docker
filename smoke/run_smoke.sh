#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

normalize_file() {
  local src="$1"
  local dst="$2"
  tr -d '\r' < "$src" > "$dst"
}

run_ini_dry_run() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export INI_Public=true
    export INI_PublicName="New Name"
    export INI_Mods="ModA"
    export INI_ServerOptions__PVP=false
    export INI_ServerOptions__DropOffWhiteList=false
    export INI_CTRL_DRY_RUN=true
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini" "INI_"
  )
  normalize_file "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.norm.ini"
  normalize_file "${TMP_DIR}/sample.ini" "${TMP_DIR}/sample.out.ini"
  if ! diff -u "${TMP_DIR}/sample.norm.ini" "${TMP_DIR}/sample.out.ini" >/dev/null; then
    echo "INI dry-run modified file" >&2
    exit 1
  fi
}

run_ini_load() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export INI_Public=true
    export INI_PublicName="New Name"
    export INI_Mods="ModA"
    export INI_ServerOptions__PVP=false
    export INI_ServerOptions__DropOffWhiteList=false
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini" "INI_"
  )
  normalize_file "${SCRIPT_DIR}/expected.ini" "${TMP_DIR}/expected.norm.ini"
  normalize_file "${TMP_DIR}/sample.ini" "${TMP_DIR}/sample.out.ini"
  diff -u "${TMP_DIR}/expected.norm.ini" "${TMP_DIR}/sample.out.ini" >/dev/null
}

run_lua_dry_run() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export LUA_sample_sandbox__ZombieLore_Transmission=4
    export LUA_sample_sandbox__World_Event=2
    export LUA_CTRL_DRY_RUN=true
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "LUA_sample_sandbox__" "SandboxVars"
  )
  normalize_file "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.norm.lua"
  normalize_file "${TMP_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.out.lua"
  if ! diff -u "${TMP_DIR}/sample_sandbox.norm.lua" "${TMP_DIR}/sample_sandbox.out.lua" >/dev/null; then
    echo "Lua dry-run modified file" >&2
    exit 1
  fi
}

run_lua_load() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export LUA_sample_sandbox__ZombieLore_Transmission=4
    export LUA_sample_sandbox__World_Event=2
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "LUA_sample_sandbox__" "SandboxVars"
  )
  if ! grep -q "Transmission = 4" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua apply did not update Transmission" >&2
    exit 1
  fi
  if ! grep -q "Event = 2" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua apply did not update Event" >&2
    exit 1
  fi
}

run_env_docs_smoke() {
  local env_dir="${TMP_DIR}/env_sources"
  local out_json="${TMP_DIR}/env.json"
  mkdir -p "${env_dir}/Server"
  cp "${SCRIPT_DIR}/sample.ini" "${env_dir}/Server/sample.ini"
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${env_dir}/Server/sample_SandboxVars.lua"

  ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${out_json}" IMAGE_TAG="smoke" bash "${ROOT_DIR}/scripts/generate_env_docs.sh"

  if [ ! -s "${out_json}" ]; then
    echo "Env docs did not generate output" >&2
    exit 1
  fi
  if ! grep -Eq '"env_name"[[:space:]]*:[[:space:]]*"INI_Public"' "${out_json}"; then
    echo "Env docs missing INI_Public" >&2
    exit 1
  fi
  if ! grep -Eq '"env_name"[[:space:]]*:[[:space:]]*"LUA_SandboxVars__ZombieLore_Transmission"' "${out_json}"; then
    echo "Env docs missing LUA_SandboxVars__ZombieLore_Transmission" >&2
    exit 1
  fi
  if ! grep -Eq '"env_hooks"[[:space:]]*:' "${out_json}"; then
    echo "Env docs missing env_hooks section" >&2
    exit 1
  fi
  if ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"ADMINPASSWORD"' "${out_json}"; then
    echo "Env docs missing env_hooks ADMINPASSWORD" >&2
    exit 1
  fi
}

echo "Running INI helper smoke tests..."
run_ini_dry_run
echo "INI dry-run ok"
run_ini_load
echo "INI apply ok"

echo "Running Lua helper smoke tests..."
run_lua_dry_run
echo "Lua dry-run ok"
run_lua_load
echo "Lua apply ok"

echo "Running env docs smoke test..."
run_env_docs_smoke
echo "Env docs ok"

echo "Smoke tests passed."
