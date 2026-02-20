#!/bin/bash

DOCS_INI_PREFIX="${DOCS_INI_PREFIX:-ini__}"
DOCS_LUA_PREFIX="${DOCS_LUA_PREFIX:-lua__}"

env_name_base_from_path() {
  local file_path="$1"
  local extension="$2"
  basename "${file_path}" "${extension}"
}

env_name_file_key() {
  local file_path="$1"
  local extension="$2"
  env_name_base_from_path "${file_path}" "${extension}"
}

env_name_file_id_from_base() {
  local base_name="$1"
  local server_name="$2"
  if [ -n "${server_name}" ] && [ "${base_name}" = "${server_name}" ]; then
    printf ''
  elif [ -n "${server_name}" ] && [[ "${base_name}" == "${server_name}_"* ]]; then
    printf '%s' "${base_name#${server_name}_}"
  else
    printf '%s' "${base_name}"
  fi
}

legacy_ini_env_prefix() {
  local file_id="$1"
  if [ -z "${file_id}" ]; then
    printf 'INI_'
  else
    printf 'INI_%s__' "${file_id}"
  fi
}

legacy_lua_env_prefix() {
  local file_id="$1"
  if [ -z "${file_id}" ]; then
    printf 'LUA_'
  else
    printf 'LUA_%s__' "${file_id}"
  fi
}

lua_detect_root_prefix() {
  local lua_file="$1"
  awk '
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^--/) next
      if (line ~ /^return[ \t]*\{[ \t]*$/) { print ""; exit }
      if (match(line, /^([A-Za-z0-9_]+)[ \t]*=[ \t]*\{[ \t]*$/, m)) { print m[1]; exit }
    }
    END { if (NR == 0) print "" }
  ' "${lua_file}"
}
