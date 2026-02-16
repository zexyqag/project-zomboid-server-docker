DESCRIPTION="Set JVM maximum heap size (e.g., 4096m)."
REPLACES=""
DEPENDS_ON="MIN_MEMORY"

manual_apply() {
  if [ -n "${MIN_MEMORY:-}" ] && [ -n "${MAX_MEMORY:-}" ] && [ -z "${JAVA_MEM_DONE:-}" ]; then
    ARGS="${ARGS} -Xms${MIN_MEMORY} -Xmx${MAX_MEMORY}"
    export JAVA_MEM_DONE=true
  fi
}
