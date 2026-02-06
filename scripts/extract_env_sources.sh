#!/bin/bash

set -euo pipefail

OUT_DIR="${1:-/out}"
STEAM_DIR="${STEAMAPPDIR:-/home/steam/pz-dedicated}"

mkdir -p "${OUT_DIR}/ini" "${OUT_DIR}/lua"

if [ ! -d "${STEAM_DIR}" ]; then
  echo "Error: STEAM_DIR not found: ${STEAM_DIR}" >&2
  exit 1
fi

copy_with_parents() {
  local src="$1"
  local dest_root="$2"
  local rel_path

  rel_path="${src#${STEAM_DIR}/}"
  mkdir -p "${dest_root}/$(dirname "${rel_path}")"
  cp -f "${src}" "${dest_root}/${rel_path}"
}

# Collect INI files from media directories.
if [ -d "${STEAM_DIR}/media" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${OUT_DIR}/ini"
  done < <(find "${STEAM_DIR}/media" -type f -name "*.ini" -print0)
fi

# Collect Sandbox preset Lua files.
if [ -d "${STEAM_DIR}/media/lua/shared/Sandbox" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${OUT_DIR}/lua"
  done < <(find "${STEAM_DIR}/media/lua/shared/Sandbox" -type f -name "*.lua" -print0)
fi

# Collect server Lua config files as a fallback.
if [ -d "${STEAM_DIR}/media/lua/server" ]; then
  while IFS= read -r -d '' file; do
    copy_with_parents "${file}" "${OUT_DIR}/lua"
  done < <(find "${STEAM_DIR}/media/lua/server" -type f -name "*.lua" -print0)
fi

echo "Env sources extracted to ${OUT_DIR}"