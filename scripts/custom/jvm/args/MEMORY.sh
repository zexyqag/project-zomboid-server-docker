DESCRIPTION="Set JVM min/max heap size (e.g., 2048m)."
REPLACES=""
DEPENDS_ON="MAX_MEMORY"

manual_apply() {
  if [ -z "${JAVA_MEM_DONE:-}" ] && [ -n "${MEMORY:-}" ]; then
    ARGS="${ARGS} -Xms${MEMORY} -Xmx${MEMORY}"
    export JAVA_MEM_DONE=true
  fi
}
