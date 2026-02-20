#!/bin/bash

set -euo pipefail

OUT_DIR="${1:-/out}"
STEAM_DIR="${STEAMAPPDIR:-/home/steam/pz-dedicated}"
ZOMBOID_DIR="${HOMEDIR:-/home/steam}/Zomboid"
SERVER_DIR="${ZOMBOID_DIR}/Server"

mkdir -p "${OUT_DIR}/ini" "${OUT_DIR}/lua"

if [ ! -d "${STEAM_DIR}" ]; then
  echo "Error: STEAM_DIR not found: ${STEAM_DIR}" >&2
  exit 1
fi

copy_with_parents() {
  local src="$1"
  local base_root="$2"
  local dest_root="$3"
  local rel_path

  rel_path="${src#${base_root}/}"
  mkdir -p "${dest_root}/$(dirname "${rel_path}")"
  cp -f "${src}" "${dest_root}/${rel_path}"
}

if [ -d "${SERVER_DIR}" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${ZOMBOID_DIR}" "${OUT_DIR}"
  done < <(find "${SERVER_DIR}" -type f \( -name "*.ini" -o -name "*.lua" \) -print0)
fi

# Collect INI files from media directories.
if [ -d "${STEAM_DIR}/media" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${STEAM_DIR}" "${OUT_DIR}/ini"
  done < <(find "${STEAM_DIR}/media" -type f -name "*.ini" -print0)
fi

# Collect Sandbox preset Lua files.
if [ -d "${STEAM_DIR}/media/lua/shared/Sandbox" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${STEAM_DIR}" "${OUT_DIR}/lua"
  done < <(find "${STEAM_DIR}/media/lua/shared/Sandbox" -type f -name "*.lua" -print0)
fi

# Collect server Lua config files as a fallback.
if [ -d "${STEAM_DIR}/media/lua/server" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${STEAM_DIR}" "${OUT_DIR}/lua"
  done < <(find "${STEAM_DIR}/media/lua/server" -type f -name "*.lua" -print0)
fi

if [ -d "${SERVER_DIR}" ]; then
  echo "Env sources extracted from ${SERVER_DIR} and media sources to ${OUT_DIR}"
else
  echo "Env sources extracted to ${OUT_DIR}"
fi