DESCRIPTION="Enable VAC on Steam servers (true/false)."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  if [ -n "${STEAMVAC:-}" ] && { [ "${STEAMVAC,,}" == "true" ] || [ "${STEAMVAC,,}" == "false" ]; }; then
    ARGS="${ARGS} -steamvac ${STEAMVAC,,}"
  fi
}
