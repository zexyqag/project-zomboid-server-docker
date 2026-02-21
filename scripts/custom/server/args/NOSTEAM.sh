DESCRIPTION="Disable Steam integration (true/false)."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if is_true "${NOSTEAM:-}"; then
    ARGS="${ARGS} -nosteam"
  fi
}
