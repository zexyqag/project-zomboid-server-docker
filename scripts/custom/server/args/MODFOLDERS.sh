DESCRIPTION="Mod folder order/source list (e.g., workshop,steam,mods)."
REPLACES=""
DEPENDS_ON="ARGS_JAVA_END"

manual_apply() {
  if [ -n "${MODFOLDERS:-}" ]; then
    ARGS="${ARGS} -modfolders ${MODFOLDERS}"
  fi
}
