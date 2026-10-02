#!/bin/bash
# Prints every env var this image understands for the server's current INI and Lua files,
# including settings added by mods. Optional argument: a case-insensitive filter.

set -euo pipefail

out="$(mktemp)"
trap 'rm -f "${out}"' EXIT

SERVERNAME=pzserver ENV_SOURCES_DIR="${HOMEDIR}/Zomboid" OUTPUT_PATH="${out}" IMAGE_TAG=local \
  bash /server/scripts/generate_env_docs.sh >/dev/null

jq -r '.env | .. | objects | select(has("env_name") and .env_name != "") | [.env_name, .description] | @tsv' "${out}" \
  | sort -u \
  | grep -i -- "${1:-}"
