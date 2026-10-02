#!/bin/bash
# Installs the game into STEAMAPPDIR from the Steam branch in GAME_BRANCH and keeps it up to date.

game_build() {
  sed -n 's/^[[:space:]]*"buildid"[[:space:]]*"\([0-9]*\)".*/\1/p' \
    "${STEAMAPPDIR}/steamapps/appmanifest_${STEAMAPPID}.acf" 2>/dev/null | head -n 1
}

update_game() {
  local branch="${GAME_BRANCH:-public}" marker="${STEAMAPPDIR}/.game-branch" installed="" log status
  local beta_args=() validate=()
  [ -f "${marker}" ] && installed="$(<"${marker}")"

  if [ -f "${STEAMAPPDIR}/start-server.sh" ] && [ "${installed}" = "${branch}" ] && ! is_true "${GAME_UPDATE:-true}"; then
    echo "Game: ${branch} branch, build $(game_build), not checked for updates (GAME_UPDATE=false)"
    return 0
  fi

  # "-beta public" is not a valid beta, so the flag is only passed for other branches.
  [ "${branch}" = public ] || beta_args=(-beta "${branch}")
  if [ -f "${STEAMAPPDIR}/start-server.sh" ] && [ "${installed}" != "${branch}" ]; then
    # Without -beta SteamCMD keeps updating from the beta it last installed, so it has to forget
    # the install and check every file against the new branch.
    echo "Game: switching from the ${installed:-unknown} branch to ${branch}"
    rm -f "${STEAMAPPDIR}/steamapps/appmanifest_${STEAMAPPID}.acf"
    validate=(validate)
  fi

  echo "Game: installing or updating the ${branch} branch with SteamCMD"
  log="$(mktemp)"
  # SteamCMD can fail the first attempt with "Missing configuration" until the app info is cached.
  for attempt in 1 2 3; do
    # In the background, so a stop signal doesn't wait for a download to finish.
    (
      set -o pipefail
      "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" +login anonymous \
        +app_update "${STEAMAPPID}" "${beta_args[@]}" "${validate[@]}" +quit 2>&1 | tee "${log}"
    ) &
    status=0
    wait "$!" || status=$?
    # SteamCMD doesn't end its output with a newline, so the next line would be appended to its last.
    [ -z "$(tail -c 1 "${log}")" ] || echo
    if [ "${status}" = 0 ] && grep -q "Success! App '${STEAMAPPID}'" "${log}" && [ -f "${STEAMAPPDIR}/start-server.sh" ]; then
      rm -f "${log}"
      printf '%s\n' "${branch}" > "${marker}"
      echo "Game: ${branch} branch, build $(game_build)"
      return 0
    fi
    [ "${attempt}" = 3 ] || sleep 10
  done
  rm -f "${log}"
  echo "Error: SteamCMD could not install or update the ${branch} branch of the game; its output is above." >&2
  if [ -f "${STEAMAPPDIR}/start-server.sh" ] && [ "${installed}" = "${branch}" ]; then
    echo "GAME_UPDATE=false starts the installed game without contacting Steam." >&2
  fi
  exit 1
}
