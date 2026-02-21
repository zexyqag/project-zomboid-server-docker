DESCRIPTION="Update steamclient.so in the server installation before launch."
REPLACES=""

manual_apply() {
  if is_true "${FORCESTEAMCLIENTSOUPDATE:-}"; then
    echo "FORCESTEAMCLIENTSOUPDATE variable is set, updating steamclient.so in Zomboid's server"
    cp "${STEAMCMDDIR}/linux64/steamclient.so" "${STEAMAPPDIR}/linux64/steamclient.so"
    cp "${STEAMCMDDIR}/linux32/steamclient.so" "${STEAMAPPDIR}/steamclient.so"
  fi
}
