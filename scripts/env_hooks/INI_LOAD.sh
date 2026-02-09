DESCRIPTION="Load INI_ overrides from environment using apply_ini_vars.sh."
REPLACES=""
DEPENDS_ON="ADMINPASSWORD PASSWORD RCONPASSWORD MOD_IDS WORKSHOP_IDS DISABLE_ANTICHEAT MAP_SCAN_VERBOSE"

manual_apply() {
  if [ -n "${INI_LOAD_DONE:-}" ]; then
    return
  fi
  export INI_LOAD_DONE=true
  server_dir="${HOMEDIR}/Zomboid/Server"
  shopt -s nullglob
  ini_files=("${server_dir}"/*.ini)
  shopt -u nullglob

  for ini_file in "${ini_files[@]}"; do
    [ -f "${ini_file}" ] || continue
    base_name="$(basename "${ini_file}" .ini)"
    if [ -n "${SERVERNAME:-}" ] && [ "${base_name}" = "${SERVERNAME}" ]; then
      file_id=""
    elif [ -n "${SERVERNAME:-}" ] && [[ "${base_name}" == "${SERVERNAME}_"* ]]; then
      file_id="${base_name#${SERVERNAME}_}"
    else
      file_id="${base_name}"
    fi

    if [ -z "${file_id}" ]; then
      env_prefix="INI_"
    else
      env_prefix="INI_${file_id}__"
    fi

    /server/scripts/apply_ini_vars.sh "${ini_file}" "${env_prefix}"
  done
}
