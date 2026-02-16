DESCRIPTION="Override the data cache directory."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if [ -n "${CACHEDIR:-}" ]; then
    ARGS="${ARGS} -cachedir=${CACHEDIR}"
  fi
}
