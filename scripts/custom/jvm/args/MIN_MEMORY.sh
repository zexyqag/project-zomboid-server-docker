DESCRIPTION="Set JVM minimum heap size (e.g., 1024m)."
REPLACES=""

manual_apply() {
  if [ -n "${MIN_MEMORY:-}" ] && [ -n "${MAX_MEMORY:-}" ] && [ -z "${JAVA_MEM_DONE:-}" ]; then
    ARGS="${ARGS} -Xms${MIN_MEMORY} -Xmx${MAX_MEMORY}"
    export JAVA_MEM_DONE=true
  fi
}
