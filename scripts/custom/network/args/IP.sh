DESCRIPTION="Bind address for the server (-ip)."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  if [ -n "${IP:-}" ]; then
    ARGS="${ARGS} -ip ${IP}"
  fi
}
