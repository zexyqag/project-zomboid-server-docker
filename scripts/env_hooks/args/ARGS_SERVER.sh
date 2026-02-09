DESCRIPTION="Builds server arguments for launch."
REPLACES=""
DEPENDS_ON="ARGS_JAVA"

manual_apply() {
  # Runs a coop server instead of a dedicated server. Disables the default admin from being accessible.
  # - Default: Disabled
  if is_true "${COOP:-}"; then
    ARGS="${ARGS} -coop"
  fi

  # Disables Steam integration on server.
  # - Default: Enabled
  if is_true "${NOSTEAM:-}"; then
    ARGS="${ARGS} -nosteam"
  fi

  # Sets the path for the game data cache dir.
  # - Default: ~/Zomboid
  # - Example: /server/Zomboid/data
  if [ -n "${CACHEDIR:-}" ]; then
    ARGS="${ARGS} -cachedir=${CACHEDIR}"
  fi

  # Option to control where mods are loaded from and the order. Any of the 3 keywords may be left out and may appear in any order.
  # - Default: workshop,steam,mods
  # - Example: mods,steam
  if [ -n "${MODFOLDERS:-}" ]; then
    ARGS="${ARGS} -modfolders ${MODFOLDERS}"
  fi

  # Launches the game in debug mode.
  # - Default: Disabled
  if is_true "${DEBUG:-}"; then
    ARGS="${ARGS} -debug"
  fi

  if [ -n "${ADMINUSERNAME:-}" ]; then
    ARGS="${ARGS} -adminusername ${ADMINUSERNAME}"
  fi

  ARGS="${ARGS} -servername \"${SERVERNAME}\""
}
