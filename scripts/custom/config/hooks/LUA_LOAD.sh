DOCS_IGNORE="true"
DESCRIPTION="Load docs-style Lua overrides from environment using apply_lua_vars.sh."
REPLACES=""
DEPENDS_ON="SERVERPRESET"

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${hook_dir}/../../../lib/env_name_codec.sh"

manual_apply() {
  server_dir="${HOMEDIR}/Zomboid/Server"
  shopt -s nullglob
  lua_files=("${server_dir}"/*.lua)
  shopt -u nullglob

  for lua_file in "${lua_files[@]}"; do
    [ -f "${lua_file}" ] || continue
    root_prefix="$(lua_detect_root_prefix "${lua_file}")"
    bash "${SCRIPT_DIR}/apply_lua_vars.sh" "${lua_file}" "${root_prefix}"
  done
}
