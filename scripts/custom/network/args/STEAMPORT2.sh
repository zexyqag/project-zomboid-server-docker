DESCRIPTION="Steam server port 2."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  if [ -n "${STEAMPORT2:-}" ]; then
    ARGS="${ARGS} -steamport2 ${STEAMPORT2}"
  fi
}
