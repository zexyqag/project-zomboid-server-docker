DESCRIPTION="RCON password (preferred over INI_RCONPassword)."
REPLACES="INI_RCONPassword"

manual_apply() {
  safe_update_ini_key "${INI_FILE}" "RCONPassword" "RCONPASSWORD" "RCONPASSWORD_FILE"
}
