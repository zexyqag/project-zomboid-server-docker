DOCS_IGNORE="true"
DESCRIPTION="Load docs-style INI overrides from environment using apply_ini_vars.sh."
REPLACES=""
DEPENDS_ON="ADMINPASSWORD PASSWORD RCONPASSWORD MOD_IDS WORKSHOP_IDS DISABLE_ANTICHEAT MAP_SCAN_VERBOSE"

manual_apply() {
  server_dir="${HOMEDIR}/Zomboid/Server"
  shopt -s nullglob
  ini_files=("${server_dir}"/*.ini)
  shopt -u nullglob

  for ini_file in "${ini_files[@]}"; do
    [ -f "${ini_file}" ] || continue
    bash "${SCRIPT_DIR}/apply_ini_vars.sh" "${ini_file}"
  done
}
