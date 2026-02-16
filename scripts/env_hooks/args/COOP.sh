DESCRIPTION="Run a coop server instead of dedicated (true/false)."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if is_true "${COOP:-}"; then
    ARGS="${ARGS} -coop"
  fi
}
