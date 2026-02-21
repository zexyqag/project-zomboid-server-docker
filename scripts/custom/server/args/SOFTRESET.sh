DESCRIPTION="Enable soft reset on startup."
REPLACES=""
DEPENDS_ON="MEMORY"

manual_apply() {
  if is_true "${SOFTRESET:-}"; then
    ARGS="${ARGS} -Dsoftreset"
  fi
}
