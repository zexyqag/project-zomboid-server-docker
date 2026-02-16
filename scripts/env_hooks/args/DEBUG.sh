DESCRIPTION="Launch server with debug flag (true/false)."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if is_true "${DEBUG:-}"; then
    ARGS="${ARGS} -debug"
  fi
}
