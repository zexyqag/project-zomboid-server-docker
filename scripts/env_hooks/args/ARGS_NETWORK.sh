DESCRIPTION="Builds network arguments for launch."
REPLACES=""
DEPENDS_ON="ARGS_SERVER"

manual_apply() {
  # Option to handle multiple network cards. Example: 127.0.0.1
  # Use -ip only; passing a raw positional IP can cause unexpected arg parsing.
  if [ -n "${IP:-}" ]; then
    ARGS="${ARGS} -ip ${IP}"
  fi

  # Set the DefaultPort for the server. Example: 16261
  if [ -n "${PORT:-}" ]; then
    ARGS="${ARGS} -port ${PORT}"
  fi

  # Option to enable/disable VAC on Steam servers. On the server command-line use -steamvac true/false. In the server's INI file, use STEAMVAC=true/false.
  if [ -n "${STEAMVAC:-}" ] && { [ "${STEAMVAC,,}" == "true" ] || [ "${STEAMVAC,,}" == "false" ]; }; then
    ARGS="${ARGS} -steamvac ${STEAMVAC,,}"
  fi

  # Steam servers require two additional ports to function (I'm guessing they are both UDP ports, but you may need TCP as well).
  # These are in addition to the DefaultPort= setting. These can be specified in two ways:
  #  - In the server's INI file as SteamPort1= and SteamPort2=.
  #  - Using STEAMPORT1 and STEAMPORT2 variables.
  if [ -n "${STEAMPORT1:-}" ]; then
    ARGS="${ARGS} -steamport1 ${STEAMPORT1}"
  fi
  if [ -n "${STEAMPORT2:-}" ]; then
    ARGS="${ARGS} -steamport2 ${STEAMPORT2}"
  fi
}
