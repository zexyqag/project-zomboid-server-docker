DESCRIPTION="Server password (preferred over ini__pzserver__Password)."
REPLACES="ini__pzserver__Password"

manual_apply() {
  local value
  value="$(read_secret PASSWORD PASSWORD_FILE)"
  if [ -n "${value}" ]; then
    set_ini_value "Password" "${value}"
  fi
}
