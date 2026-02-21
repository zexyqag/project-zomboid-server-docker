DESCRIPTION="Steam server port 1."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  if [ -n "${STEAMPORT1:-}" ]; then
    ARGS="${ARGS} -steamport1 ${STEAMPORT1}"
  fi
}
