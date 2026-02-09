DESCRIPTION="Server password (preferred over INI_Password)."
REPLACES="INI_Password"

manual_apply() {
  safe_update_ini_key "${INI_FILE}" "Password" "PASSWORD" "PASSWORD_FILE"
}
