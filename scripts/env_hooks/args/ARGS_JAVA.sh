DESCRIPTION="Builds JVM arguments for server launch."
REPLACES=""

manual_apply() {
  # Set the server memory. Units are accepted (1024m=1Gig, 2048m=2Gig, 4096m=4Gig): Example: 1024m
  if [ -n "${MIN_MEMORY:-}" ] && [ -n "${MAX_MEMORY:-}" ]; then
    ARGS="${ARGS} -Xms${MIN_MEMORY} -Xmx${MAX_MEMORY}"
  elif [ -n "${MEMORY:-}" ]; then
    ARGS="${ARGS} -Xms${MEMORY} -Xmx${MEMORY}"
  fi

  # Option to perform a Soft Reset
  if is_true "${SOFTRESET:-}"; then
    ARGS="${ARGS} -Dsoftreset"
  fi

  # End of Java arguments
  ARGS="${ARGS} -- "
}
