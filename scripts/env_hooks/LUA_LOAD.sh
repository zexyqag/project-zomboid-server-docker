DESCRIPTION="Load Lua overrides from environment using apply_lua_vars.sh."
REPLACES=""
DEPENDS_ON="SERVERPRESET"

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
    base_name="$(basename "${lua_file}" .lua)"

    root_prefix="$(awk '
      {
        line=$0
        sub(/^[ \t]+/, "", line)
        if (line ~ /^--/) next
        if (line ~ /^return[ \t]*\{[ \t]*$/) { print ""; exit }
        if (match(line, /^([A-Za-z0-9_]+)[ \t]*=[ \t]*\{[ \t]*$/, m)) { print m[1]; exit }
      }
      END { if (NR == 0) print "" }
    ' "${lua_file}")"

    if [ -n "${SERVERNAME:-}" ] && [ "${base_name}" = "${SERVERNAME}" ]; then
      file_id=""
    elif [ -n "${SERVERNAME:-}" ] && [[ "${base_name}" == "${SERVERNAME}_"* ]]; then
      file_id="${base_name#${SERVERNAME}_}"
    else
      file_id="${base_name}"
    fi

    if [ -z "${file_id}" ]; then
      env_prefix="LUA_"
    else
      env_prefix="LUA_${file_id}__"
    fi

    /server/scripts/apply_lua_vars.sh "${lua_file}" "${env_prefix}" "${root_prefix}"
  done
}
