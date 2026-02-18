#!/bin/bash

set -euo pipefail

if [ "${ENV_DOCS_TRACE:-}" = "1" ]; then
  set -x
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${OUTPUT_PATH:-${repo_root}/docs/env.json}"
sources_root="${ENV_SOURCES_DIR:-${repo_root}/docs/env_sources}"
image_tag="${IMAGE_TAG:-}"

env_hooks_dir="${repo_root}/scripts/env_hooks"
env_declarations_dir="${repo_root}/scripts/env_hooks/vars"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

ini_items_file="${tmp_dir}/ini_items.tsv"
lua_items_file="${tmp_dir}/lua_items.tsv"
handcrafted_file="${tmp_dir}/handcrafted.tsv"
env_hooks_items_file="${tmp_dir}/env_hooks_items.tsv"
env_declarations_items_file="${tmp_dir}/env_declarations_items.tsv"
declared_envs_file="${tmp_dir}/declared_envs.txt"

: > "${ini_items_file}"
: > "${lua_items_file}"
: > "${handcrafted_file}"
: > "${env_hooks_items_file}"
: > "${env_declarations_items_file}"
: > "${declared_envs_file}"

env_hook_replaces=""

extract_manual_value() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1==k {val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); gsub(/^"|"$|^\047|\047$/, "", val); print val; exit}' "$file"
}

if [ -d "${env_hooks_dir}" ]; then
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    docs_ignore="$(extract_manual_value "DOCS_IGNORE" "${file}")"
    case "${docs_ignore,,}" in
      1|true|yes|y|on) continue ;;
    esac
    env_name="$(basename "${file}" .sh)"
    description="$(extract_manual_value "DESCRIPTION" "${file}")"
    replaces="$(extract_manual_value "REPLACES" "${file}")"
    printf '%s\t%s\t%s\n' "${env_name}" "${description}" "${replaces}" >> "${env_hooks_items_file}"
    printf '%s\n' "${env_name}" >> "${declared_envs_file}"
  done <<< "$(find "${env_hooks_dir}" -type d -name vars -prune -o -type f -name '*.sh' -print | sort)"
fi

if [ -d "${env_declarations_dir}" ]; then
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    docs_ignore="$(extract_manual_value "DOCS_IGNORE" "${file}")"
    case "${docs_ignore,,}" in
      1|true|yes|y|on) continue ;;
    esac
    env_name="$(basename "${file}" .sh)"
    description="$(extract_manual_value "DESCRIPTION" "${file}")"
    replaces="$(extract_manual_value "REPLACES" "${file}")"
    printf '%s\t%s\t%s\n' "${env_name}" "${description}" "${replaces}" >> "${env_declarations_items_file}"
    printf '%s\n' "${env_name}" >> "${declared_envs_file}"
  done <<< "$(find "${env_declarations_dir}" -type f -name '*.sh' | sort)"
fi

if [ -s "${env_hooks_items_file}" ]; then
  env_hook_replaces="$(awk -F '\t' '{print $3}' "${env_hooks_items_file}" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"
fi

if [ -s "${declared_envs_file}" ]; then
  sort -u "${declared_envs_file}" -o "${declared_envs_file}"
fi

is_declared() {
  local key="$1"
  if [ -s "${declared_envs_file}" ] && grep -qx "${key}" "${declared_envs_file}"; then
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

  if [ -d "${env_hooks_dir}" ]; then
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      scan_files+=("${file}")
    done <<< "$(find "${env_hooks_dir}" -type d -name vars -prune -o -type f -name '*.sh' -print | sort)"
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

  ref_envs="$(comm -23 <(printf '%s\n' "${refs}" | sort -u) <(printf '%s\n' "${assigned}" | sort -u))"
  declared_only=""
  if [ -s "${env_declarations_items_file}" ]; then
    declared_only="$(awk -F '\t' '{print $1}' "${env_declarations_items_file}" | sed '/^$/d' | sort -u)"
  fi
  env_list="$(printf '%s\n%s\n' "${ref_envs}" "${declared_only}" | sed '/^$/d' | sort -u)"

  get_env_description() {
    local name="$1"
    local desc=""
    if [ -s "${env_hooks_items_file}" ]; then
      desc="$(awk -F '\t' -v n="${name}" '$1==n {print $2; exit}' "${env_hooks_items_file}")"
    fi
    if [ -z "${desc}" ] && [ -s "${env_declarations_items_file}" ]; then
      desc="$(awk -F '\t' -v n="${name}" '$1==n {print $2; exit}' "${env_declarations_items_file}")"
    fi
    printf '%s' "${desc}"
  }

  while IFS= read -r env_name; do
    [ -z "${env_name}" ] && continue
    case "${env_name}" in
      INI_*|LUA_*) continue ;;
    esac
    if [ "$(is_declared "${env_name}")" != "true" ]; then
      continue
    fi
    source_path="scripts/env_hooks"
    group_name="env_hooks"
    if [ -f "${env_hooks_dir}/${env_name}.sh" ]; then
      source_path="scripts/env_hooks"
      group_name="env_hooks"
    elif [ -f "${env_hooks_dir}/args/${env_name}.sh" ]; then
      source_path="scripts/env_hooks/args"
      group_name="args"
    elif [ -f "${env_declarations_dir}/${env_name}.sh" ]; then
      source_path="scripts/env_hooks/vars"
      group_name="vars"
    fi
    description="$(get_env_description "${env_name}")"
    printf '%s\t%s\t%s\t%s\n' "${env_name}" "${source_path}" "${group_name}" "${description}" >> "${handcrafted_file}"
  done <<< "${env_list}"
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
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  BEGIN { section=""; comment_block=""; group="INI" }
  {
    line=$0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line == "") { comment_block=""; next }
    if (line ~ /^[;#]/) {
      c=line
      sub(/^[;#][ \t]*/, "", c)
      if (comment_block != "") comment_block=comment_block "\n" c
      else comment_block=c
      next
    }
    if (line ~ /^\[[^\]]+\]/) {
      section=line
      sub(/^\[/, "", section)
      sub(/\].*$/, "", section)
      group=section
      comment_block=""
      next
    }
    if (line ~ /^[^=]+=.*$/) {
      key=line
      sub(/=.*/, "", key)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      desc=""
      inline=""
      pos=index(line, ";")
      pos2=index(line, "#")
      if (pos == 0 || (pos2 > 0 && pos2 < pos)) pos=pos2
      if (pos > 0) {
        inline=substr(line, pos + 1)
        inline=trim(inline)
      }
      if (inline != "") desc=inline
      else if (comment_block != "") desc=comment_block
      env=(section=="" ? env_prefix key : env_prefix section "__" key)
      print env "\t" group "\t" section "\t" key "\t" file "\t" desc
      comment_block=""
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
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  BEGIN { in_table=0; depth=0; comment_block=""; top_group="" }
  {
    line=$0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line == "") { comment_block=""; next }
    if (line ~ /^--/) {
      c=line
      sub(/^--[ \t]?/, "", c)
      if (comment_block != "") comment_block=comment_block "\n" c
      else comment_block=c
      next
    }
    if (!in_table) {
      if (line ~ /^return[ \t]*\{$/) {
        in_table=1
        depth=0
        if (top_group == "") top_group="Lua"
        next
      }
      if (line ~ /^[A-Za-z0-9_]+[ \t]*=[ \t]*\{$/) {
        key=line
        sub(/^[ \t]*/, "", key)
        sub(/[ \t]*=.*$/, "", key)
        in_table=1
        depth=0
        if (top_group == "") top_group=key
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
      desc=""
      inline=""
      pos=index(line, "--")
      if (pos > 0) {
        inline=substr(line, pos + 2)
        inline=trim(inline)
        line=substr(line, 1, pos - 1)
      }
      if (inline != "") desc=inline
      else if (comment_block != "") desc=comment_block
      path=join_path(key)
      n=split(path, parts, ".")
      env=env_prefix
      for (i=1; i<=n; i++) {
        env=env "_" encode(parts[i])
      }
      subgroup=path
      sub(/\..*$/, "", subgroup)
      print env "\t" top_group "\t" subgroup "\t" path "\t" file "\t" desc
      comment_block=""
    }
  }
  ' "${file}" >> "${lua_items_file}"
done <<< "${lua_files}"

collect_handcrafted_envs

ini_json="$(awk -F '\t' '
  {
    env=$1; group=$2; src=$5; desc=$6
    if (!(env in groupmap)) { groupmap[env]=group }
    if (!(env in descmap)) { descmap[env]=desc }
    if (!(env in srcmap)) srcmap[env]=src
    else srcmap[env]=srcmap[env] "\n" src
  }
  END {
    for (env in srcmap) {
      print env "\t" groupmap[env] "\t" srcmap[env] "\t" descmap[env]
    }
  }
' "${ini_items_file}" | jq -R -s --arg manual_replaces "${env_hook_replaces}" '
  def list(s): (s|split(" ")|map(select(length>0)));
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {name:(.[0] // ""),group:(.[1] // ""),description:(.[3] // ""),sources:((.[2] // "")|tostring|split("\n")|map(select(length>0)))}
    | . as $row
    | select((list($manual_replaces) | index($row.name)) | not)
  )
  | map(. as $row | ($row.sources[]? // empty) as $src | {file:$src, group:$row.group, name:$row.name, description:$row.description, sources:$row.sources})
  | sort_by(.file, .group, .name)
  | group_by(.file)
  | map({(.[0].file): (group_by(.group) | map({(.[0].group): (map({name,description,sources}) | sort_by(.name))}) | add)})
  | add
')"

lua_json="$(awk -F '\t' '
  {
    env=$1; group=$2; subgroup=$3; src=$5; desc=$6
    if (!(env in groupmap)) groupmap[env]=group
    if (!(env in subgroupmap)) subgroupmap[env]=subgroup
    if (!(env in descmap)) descmap[env]=desc
    if (!(env in srcmap)) srcmap[env]=src
    else srcmap[env]=srcmap[env] "\n" src
  }
  END {
    for (env in srcmap) {
      print env "\t" groupmap[env] "\t" subgroupmap[env] "\t" srcmap[env] "\t" descmap[env]
    }
  }
' "${lua_items_file}" | jq -R -s --arg manual_replaces "${env_hook_replaces}" '
  def list(s): (s|split(" ")|map(select(length>0)));
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {name:(.[0] // ""),group:(.[1] // ""),subgroup:(.[2] // ""),description:(.[4] // ""),sources:((.[3] // "")|tostring|split("\n")|map(select(length>0)))}
    | . as $row
    | select((list($manual_replaces) | index($row.name)) | not)
  )
  | map(. as $row | ($row.sources[]? // empty) as $src | {file:$src, group:$row.group, subgroup:$row.subgroup, name:$row.name, description:$row.description, sources:$row.sources})
  | sort_by(.file, .group, .subgroup, .name)
  | group_by(.file)
  | map({(.[0].file): (group_by(.group) | map({(.[0].group): (group_by(.subgroup) | map({(.[0].subgroup): (map({name,description,sources}) | sort_by(.name))}) | add)}) | add)})
  | add
')"

handcrafted_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t") as $parts
    | {name:($parts[0] // ""),description:($parts[3] // ""),sources:[($parts[1] // "")],group:($parts[2] // "")}
  )
  | map(select(.name != "" and .group != ""))
  | sort_by(.group, .name)
  | group_by(.group)
  | map({(.[0].group): (map({name,description,sources}) | sort_by(.name))})
  | add
  | {env_hooks: .}
' "${handcrafted_file}")"

env_hooks_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {name:.[0],description:.[1],replaces:(.[2]|split(" ")|map(select(length>0)))}
  )
' "${env_hooks_items_file}")"
env_declarations_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {name:.[0],description:.[1],replaces:(.[2]|split(" ")|map(select(length>0)))}
  )
' "${env_declarations_items_file}")"

jq -n \
  --arg image_tag "${image_tag}" \
  --argjson handcrafted_env "${handcrafted_json}" \
  --argjson ini_env "${ini_json}" \
  --argjson lua_env "${lua_json}" \
  '{
    image_tag: $image_tag,
    handcrafted_env: $handcrafted_env,
    ini_env: $ini_env,
    lua_env: $lua_env
  }' > "${output_path}"

bash "${repo_root}/scripts/generate_env_index.sh" "$(dirname "${output_path}")" "$(dirname "${output_path}")/index.json"
