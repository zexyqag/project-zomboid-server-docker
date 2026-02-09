#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${OUTPUT_PATH:-${repo_root}/docs/env.json}"
sources_root="${ENV_SOURCES_DIR:-${repo_root}/docs/env_sources}"
image_tag="${IMAGE_TAG:-}"

entry_sh="${repo_root}/scripts/entry.sh"
env_template="${repo_root}/.env.template"
env_hooks_dir="${repo_root}/scripts/env_hooks"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

ini_items_file="${tmp_dir}/ini_items.tsv"
lua_items_file="${tmp_dir}/lua_items.tsv"
handcrafted_file="${tmp_dir}/handcrafted.tsv"
env_hooks_items_file="${tmp_dir}/env_hooks_items.tsv"
template_envs_file="${tmp_dir}/template_envs.txt"

: > "${ini_items_file}"
: > "${lua_items_file}"
: > "${handcrafted_file}"
: > "${env_hooks_items_file}"
: > "${template_envs_file}"

env_hook_replaces=""

extract_manual_value() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1==k {val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); gsub(/^"|"$|^\047|\047$/, "", val); print val; exit}' "$file"
}

if [ -d "${env_hooks_dir}" ]; then
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    env_name="$(basename "${file}" .sh)"
    description="$(extract_manual_value "DESCRIPTION" "${file}")"
    replaces="$(extract_manual_value "REPLACES" "${file}")"
    printf '%s\t%s\t%s\n' "${env_name}" "${description}" "${replaces}" >> "${env_hooks_items_file}"
  done <<< "$(find "${env_hooks_dir}" -type f -name '*.sh' | sort)"
fi

if [ -s "${env_hooks_items_file}" ]; then
  env_hook_replaces="$(awk -F '\t' '{print $3}' "${env_hooks_items_file}" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"
fi

if [ -f "${env_template}" ]; then
  grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]*=' "${env_template}" \
    | sed -e 's/^[[:space:]]*//' -e 's/=.*$//' \
    | sort -u \
    > "${template_envs_file}"
fi

is_documented() {
  local key="$1"
  if [ -s "${template_envs_file}" ] && grep -qx "${key}" "${template_envs_file}"; then
    echo "true"
  else
    echo "false"
  fi
}

collect_handcrafted_envs() {
  local refs_raw=""
  local assigned_raw=""
  local assigned_for_raw=""
  local assigned_local_raw=""
  local refs assigned assigned_for assigned_local
  local -a scan_files=()

  if [ -f "${entry_sh}" ]; then
    scan_files+=("${entry_sh}")
  fi
  if [ -d "${env_hooks_dir}" ]; then
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      scan_files+=("${file}")
    done <<< "$(find "${env_hooks_dir}" -type f -name '*.sh' | sort)"
  fi

  if [ ${#scan_files[@]} -eq 0 ]; then
    return
  fi

  for file in "${scan_files[@]}"; do
    refs_raw="${refs_raw}
$(grep -oE '\$\{[A-Z][A-Z0-9_]*\}|\$[A-Z][A-Z0-9_]*' "${file}" || true)"
    assigned_raw="${assigned_raw}
$(grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]*=' "${file}" || true)"
    assigned_for_raw="${assigned_for_raw}
$(grep -oE '\bfor[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]+in\b' "${file}" || true)"
    assigned_local_raw="${assigned_local_raw}
$(grep -oE '\blocal[[:space:]]+[A-Z][A-Z0-9_]*\b' "${file}" || true)"
  done

  refs="$(printf '%s\n' "${refs_raw}" | sed -e 's/[${}]//g' | sed '/^$/d' | sort -u)"
  assigned="$(printf '%s\n' "${assigned_raw}" | sed -e 's/^[[:space:]]*//' -e 's/=.*$//' | sed '/^$/d' | sort -u)"
  assigned_for="$(printf '%s\n' "${assigned_for_raw}" | awk '{print $2}' | sed '/^$/d' | sort -u)"
  assigned_local="$(printf '%s\n' "${assigned_local_raw}" | awk '{print $2}' | sed '/^$/d' | sort -u)"
  assigned="$(printf '%s\n%s\n%s\n' "${assigned}" "${assigned_for}" "${assigned_local}" | sed '/^$/d' | sort -u)"

  while IFS= read -r env_name; do
    [ -z "${env_name}" ] && continue
    case "${env_name}" in
      INI_*|LUA_*) continue ;;
    esac
    documented="$(is_documented "${env_name}")"
    handled_by=""
    if [ -f "${env_hooks_dir}/${env_name}.sh" ]; then
      handled_by="scripts/env_hooks/${env_name}.sh"
    fi
    printf '%s\t%s\t%s\n' "${env_name}" "${documented}" "${handled_by}" >> "${handcrafted_file}"
  done <<< "$(comm -23 <(printf '%s\n' "${refs}" | sort -u) <(printf '%s\n' "${assigned}" | sort -u))"
}

ini_files=""
lua_files=""
if [ -n "${sources_root}" ] && [ -d "${sources_root}" ]; then
  ini_files="$(find "${sources_root}" -type f -path '*Server*' -name '*.ini' | sort)"
  lua_files="$(find "${sources_root}" -type f -path '*Server*' -name '*.lua' | sort)"
else
  if [ -z "${sources_root}" ]; then
    echo "Info: ENV_SOURCES_DIR not set; skipping INI/Lua env discovery." >&2
  else
    echo "Info: ENV_SOURCES_DIR not found (${sources_root}); skipping INI/Lua env discovery." >&2
  fi
fi

server_name="${SERVERNAME:-}"
if [ -z "${server_name}" ]; then
  first_sandbox="$(printf '%s\n' "${lua_files}" | grep -E '_SandboxVars\.lua$' | head -n 1)"
  if [ -n "${first_sandbox}" ]; then
    sandbox_base="$(basename "${first_sandbox}" .lua)"
    server_name="${sandbox_base%_SandboxVars}"
  fi
fi
if [ -z "${server_name}" ]; then
  first_ini="$(printf '%s\n' "${ini_files}" | head -n 1)"
  if [ -n "${first_ini}" ]; then
    server_name="$(basename "${first_ini}" .ini)"
  fi
fi

while IFS= read -r file; do
  [ -z "${file}" ] && continue
  base_name="$(basename "${file}" .ini)"
  if [ -n "${server_name}" ] && [ "${base_name}" = "${server_name}" ]; then
    file_id=""
  elif [ -n "${server_name}" ] && [[ "${base_name}" == "${server_name}_"* ]]; then
    file_id="${base_name#${server_name}_}"
  else
    file_id="${base_name}"
  fi
  if [ -z "${file_id}" ]; then
    env_prefix="INI_"
  else
    env_prefix="INI_${file_id}__"
  fi
  awk -v file="${file}" -v env_prefix="${env_prefix}" '
  BEGIN { section="" }
  {
    line=$0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line == "" || line ~ /^[;#]/) next
    if (line ~ /^\[[^\]]+\]/) {
      section=line
      sub(/^\[/, "", section)
      sub(/\].*$/, "", section)
      next
    }
    if (line ~ /^[^=]+=.*$/) {
      key=line
      sub(/=.*/, "", key)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      env=(section=="" ? env_prefix key : env_prefix section "__" key)
      print env "\t" section "\t" key "\t" file
    }
  }
  ' "${file}" >> "${ini_items_file}"
done <<< "${ini_files}"

while IFS= read -r file; do
  [ -z "${file}" ] && continue
  base_name="$(basename "${file}" .lua)"
  if [ -n "${server_name}" ] && [ "${base_name}" = "${server_name}" ]; then
    file_id=""
  elif [ -n "${server_name}" ] && [[ "${base_name}" == "${server_name}_"* ]]; then
    file_id="${base_name#${server_name}_}"
  else
    file_id="${base_name}"
  fi
  if [ -z "${file_id}" ]; then
    env_prefix="LUA"
  else
    env_prefix="LUA_${file_id}_"
  fi
  awk -v file="${file}" -v env_prefix="${env_prefix}" '
  function encode(value,    out) {
    out=value
    gsub(/_/, "__", out)
    return out
  }
  function join_path(key,    i, path) {
    path=""
    for (i=1; i<=depth; i++) {
      if (path != "") path = path "."
      path = path stack[i]
    }
    if (path != "") path = path "." key
    else path = key
    return path
  }
  BEGIN { in_table=0; depth=0 }
  {
    line=$0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line == "" || line ~ /^--/) next
    if (!in_table) {
      if (line ~ /^return[ \t]*\{$/) {
        in_table=1
        depth=0
        next
      }
      if (line ~ /^[A-Za-z0-9_]+[ \t]*=[ \t]*\{$/) {
        in_table=1
        depth=0
        next
      }
      next
    }
    if (line ~ /^}[ \t]*,?[ \t]*$/) {
      if (depth == 0) {
        in_table=0
      } else {
        depth--
        delete stack[depth+1]
      }
      next
    }
    if (line ~ /^[A-Za-z0-9_]+[ \t]*=[ \t]*\{$/) {
      depth++
      key=line
      sub(/^[ \t]*/, "", key)
      sub(/[ \t]*=.*$/, "", key)
      stack[depth]=key
      next
    }
    if (line ~ /^[A-Za-z0-9_]+[ \t]*=[ \t]*.+$/) {
      key=line
      sub(/^[ \t]*/, "", key)
      sub(/[ \t]*=.*$/, "", key)
      path=join_path(key)
      n=split(path, parts, ".")
      env=env_prefix
      for (i=1; i<=n; i++) {
        env=env "_" encode(parts[i])
      }
      print env "\t" path "\t" file
    }
  }
  ' "${file}" >> "${lua_items_file}"
done <<< "${lua_files}"

collect_handcrafted_envs

ini_json="$(awk -F '\t' '
  {
    env=$1; sec=$2; key=$3; src=$4
    if (!(env in secmap)) { secmap[env]=sec; keymap[env]=key }
    if (!(env in srcmap)) srcmap[env]=src
    else srcmap[env]=srcmap[env] "\n" src
  }
  END {
    for (env in srcmap) {
      print env "\t" secmap[env] "\t" keymap[env] "\t" srcmap[env]
    }
  }
' "${ini_items_file}" | jq -R -s --arg manual_replaces "${env_hook_replaces}" '
  def list(s): (s|split(" ")|map(select(length>0)));
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {env_name:.[0],section:.[1],key:.[2],sources:(.[3]|split("\n")|map(select(length>0)))}
    | . as $row
    | select((list($manual_replaces) | index($row.env_name)) | not)
  )
')"

lua_json="$(awk -F '\t' '
  {
    env=$1; path=$2; src=$3
    if (!(env in pathmap)) pathmap[env]=path
    if (!(env in srcmap)) srcmap[env]=src
    else srcmap[env]=srcmap[env] "\n" src
  }
  END {
    for (env in srcmap) {
      print env "\t" pathmap[env] "\t" srcmap[env]
    }
  }
' "${lua_items_file}" | jq -R -s --arg manual_replaces "${env_hook_replaces}" '
  def list(s): (s|split(" ")|map(select(length>0)));
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {env_name:.[0],path:.[1],sources:(.[2]|split("\n")|map(select(length>0)))}
    | . as $row
    | select((list($manual_replaces) | index($row.env_name)) | not)
  )
')"

handcrafted_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t") as $parts
    | {name:$parts[0],source:"scripts/entry.sh",documented:($parts[1]=="true")}
    | (if ($parts[2] != "") then . + {handled_by:$parts[2]} else . end)
  )
' "${handcrafted_file}")"

ini_files_json="$(printf '%s\n' "${ini_files}" | jq -R -s 'split("\n")|map(select(length>0))')"
lua_files_json="$(printf '%s\n' "${lua_files}" | jq -R -s 'split("\n")|map(select(length>0))')"
env_hooks_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {name:.[0],description:.[1],replaces:(.[2]|split(" ")|map(select(length>0)))}
  )
' "${env_hooks_items_file}")"

jq -n \
  --arg generated_at "$(date -u +%F)" \
  --arg image_tag "${image_tag}" \
  --argjson ini_files "${ini_files_json}" \
  --argjson lua_files "${lua_files_json}" \
  --argjson handcrafted_env "${handcrafted_json}" \
  --argjson ini_env "${ini_json}" \
  --argjson lua_env "${lua_json}" \
  --argjson env_hooks "${env_hooks_json}" \
  '{
    generated_at: $generated_at,
    sources: {
      entry: "scripts/entry.sh",
      env_template: ".env.template",
      source_mode: (if ($ini_files | length) > 0 or ($lua_files | length) > 0 then "image_extract" else "repo_samples" end),
      ini_files: $ini_files,
      lua_files: $lua_files
    },
    image_tag: $image_tag,
    handcrafted_env: $handcrafted_env,
    ini_env: ($ini_env | sort_by(.env_name)),
    lua_env: ($lua_env | sort_by(.env_name)),
    patterns: [
      {prefix: "INI_", description: "Override server INI keys from the runtime Server INI. Use INI_Key=Value or INI_Section__Key=Value."},
      {prefix: "LUA_", description: "Override Lua files. Use LUA_<file>__Path where Path uses '_' as separators and '__' for a literal underscore."}
    ],
    env_hooks: {
      env_vars: $env_hooks,
      source: "scripts/env_hooks"
    }
  }' > "${output_path}"
