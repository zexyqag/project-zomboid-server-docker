DESCRIPTION="Load docs-style Lua overrides from environment using apply_lua_vars.sh."
REPLACES=""
DEPENDS_ON="SERVERPRESET"

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${hook_dir}/../lib/env_name_codec.sh"

manual_apply() {
  if [ -n "${LUA_LOAD_DONE:-}" ]; then
    return
  fi
  export LUA_LOAD_DONE=true
  server_dir="${HOMEDIR}/Zomboid/Server"
  shopt -s nullglob
  lua_files=("${server_dir}"/*.lua)
  shopt -u nullglob

  for lua_file in "${lua_files[@]}"; do
    [ -f "${lua_file}" ] || continue
    base_name="$(env_name_base_from_path "${lua_file}" ".lua")"
    root_prefix="$(lua_detect_root_prefix "${lua_file}")"

    file_id="$(env_name_file_id_from_base "${base_name}" "${SERVERNAME:-}")"
    env_prefix="$(legacy_lua_env_prefix "${file_id}")"

    /server/scripts/apply_lua_vars.sh "${lua_file}" "${env_prefix}" "${root_prefix}"
  done
}
