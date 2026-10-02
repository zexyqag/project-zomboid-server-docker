#!/bin/bash
# Prints "<branch> <build id>" for the Steam branches the nightly run tests: public, unstable while
# Project Zomboid has an open beta, and legacy41 for Build 41. Asks SteamCMD in the base image, or
# reads a saved app_info_print output.
# Usage: game_branches.sh [app_info_print output file]

set -euo pipefail

if [ -n "${1:-}" ]; then
  info="$(<"$1")"
else
  info="$(docker run --rm cm2network/steamcmd:root bash -c \
    '"${STEAMCMDDIR}/steamcmd.sh" +login anonymous +app_info_update 1 +app_info_print 380870 +quit')"
fi

branches="$(awk '
  { line = $0; gsub(/[\r"]/, "", line); sub(/^[ \t]+/, "", line) }
  !done && line == "branches" { inside = 1; depth = 0; next }
  inside && line == "{" { depth++; next }
  inside && line == "}" { if (--depth == 0) { inside = 0; done = 1 } next }
  inside && depth == 1 && line !~ /[ \t]/ { name = line; next }
  inside && depth == 2 && line ~ /^buildid[ \t]/ { split(line, f, /[ \t]+/); print name, f[2] }
' <<< "${info}")"

echo "Steam branches: $(cut -d' ' -f1 <<< "${branches}" | paste -sd ' ')" >&2
grep -E '^(public|unstable|legacy41) [0-9]+$' <<< "${branches}" || true
if ! grep -qE '^public [0-9]+$' <<< "${branches}"; then
  echo "Error: no build id for the public branch in SteamCMD's app info" >&2
  exit 1
fi
