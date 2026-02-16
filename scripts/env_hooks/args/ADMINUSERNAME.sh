DESCRIPTION="Admin username for the server."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if [ -n "${ADMINUSERNAME:-}" ]; then
    ARGS="${ARGS} -adminusername ${ADMINUSERNAME}"
  fi
}
