DESCRIPTION="RCON password (preferred over INI_RCONPassword)."
REPLACES="ini__pzserver__RCONPassword"

manual_apply() {
  safe_update_ini_key "${INI_FILE}" "RCONPassword" "RCONPASSWORD" "RCONPASSWORD_FILE"
}
