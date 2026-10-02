DESCRIPTION="RCON password (preferred over ini__pzserver__RCONPassword)."
REPLACES="ini__pzserver__RCONPassword"

manual_apply() {
  local value
  value="$(read_secret RCONPASSWORD RCONPASSWORD_FILE)"
  if [ -n "${value}" ]; then
    set_ini_value "RCONPassword" "${value}"
  fi
}
