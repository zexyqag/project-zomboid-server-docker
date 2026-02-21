DESCRIPTION="Load docs-style INI overrides from environment using apply_ini_vars.sh."
REPLACES=""
DEPENDS_ON="ADMINPASSWORD PASSWORD RCONPASSWORD MOD_IDS WORKSHOP_IDS DISABLE_ANTICHEAT MAP_SCAN_VERBOSE"

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${hook_dir}/../../../lib/env_name_codec.sh"

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
    base_name="$(env_name_base_from_path "${ini_file}" ".ini")"
    file_id="$(env_name_file_id_from_base "${base_name}" "${SERVERNAME:-}")"
    env_prefix="$(legacy_ini_env_prefix "${file_id}")"

    /server/scripts/apply_ini_vars.sh "${ini_file}" "${env_prefix}"
  done
}
