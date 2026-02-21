DESCRIPTION="Default server port (-port)."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  if [ -n "${PORT:-}" ]; then
    ARGS="${ARGS} -port ${PORT}"
  fi
}
