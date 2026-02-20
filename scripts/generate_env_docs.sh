#!/bin/bash

set -euo pipefail

if [ "${ENV_DOCS_TRACE:-}" = "1" ]; then
  set -x
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${OUTPUT_PATH:-${repo_root}/docs/env.json}"
sources_root="${ENV_SOURCES_DIR:-${repo_root}/docs/env_sources}"
image_tag="${IMAGE_TAG:-}"

source "${repo_root}/scripts/lib/env_name_codec.sh"

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

replacement_map_json='{}'

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
  replacement_map_json="$(
    awk -F '\t' '
      {
        replacer=$1
        replaces=$3
        gsub(/[;,]/, " ", replaces)
        n=split(replaces, parts, / +/)
        for (i=1; i<=n; i++) {
          if (parts[i] != "") {
            printf "%s\t%s\n", parts[i], replacer
          }
        }
      }
    ' "${env_hooks_items_file}" \
    | jq -R -s '
        split("\n")
        | map(select(length>0) | split("\t"))
        | group_by(.[0])
        | map({key: .[0][0], value: (map(.[1]) | unique)})
        | from_entries
      '
  )"
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
    group_name="hooks"
    if [ -f "${env_hooks_dir}/${env_name}.sh" ]; then
      source_path="scripts/env_hooks"
      group_name="hooks"
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
  file_id="$(env_name_file_id_from_base "${base_name}" "${server_name}")"
  legacy_prefix="$(legacy_ini_env_prefix "${file_id}")"
  source_id="ini_${base_name}"
  awk -v file="${file}" -v file_key="${base_name}" -v source_id="${source_id}" -v docs_ini_prefix="${DOCS_INI_PREFIX}" -v legacy_prefix="${legacy_prefix}" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function ini_split_inline(s,    i, ch, in_sq, in_dq, out, comment) {
    inline_comment=""
    in_sq=0
    in_dq=0
    out=""
    for (i=1; i<=length(s); i++) {
      ch=substr(s, i, 1)
      if (ch == "\"" && !in_sq && substr(s, i-1, 1) != "\\") {
        in_dq = !in_dq
      } else if (ch == "\047" && !in_dq && substr(s, i-1, 1) != "\\") {
        in_sq = !in_sq
      }
      if (!in_sq && !in_dq && (ch == ";" || ch == "#")) {
        comment=substr(s, i + 1)
        inline_comment=trim(comment)
        return trim(out)
      }
      out = out ch
    }
    return trim(out)
  }
  BEGIN { section=""; comment_block=""; group="" }
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
      code=ini_split_inline(line)
      key=code
      sub(/=.*/, "", key)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      desc=""
      inline=inline_comment
      if (inline != "") desc=inline
      else if (comment_block != "") desc=comment_block
      env_new=docs_ini_prefix file_key
      if (section != "") env_new=env_new "__" section
      env_new=env_new "__" key
      env_legacy=(section=="" ? legacy_prefix key : legacy_prefix section "__" key)
      print env_new "\t" file_key "\t" group "\t" source_id "\t" file "\t" desc "\t" env_legacy "\t" env_new
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
  file_id="$(env_name_file_id_from_base "${base_name}" "${server_name}")"
  legacy_prefix="$(legacy_lua_env_prefix "${file_id}")"
  legacy_prefix="${legacy_prefix%__}"
  source_id="lua_${base_name}"
  awk -v file="${file}" -v file_key="${base_name}" -v source_id="${source_id}" -v docs_lua_prefix="${DOCS_LUA_PREFIX}" -v legacy_prefix="${legacy_prefix}" '
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
  function lua_extract_key(s,    key) {
    key=s
    sub(/^[ \t]*/, "", key)
    if (key ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/) {
      sub(/[ \t]*=.*/, "", key)
      return trim(key)
    }
    if (key ~ /^\[[0-9]+\][ \t]*=/) {
      sub(/^\[/, "", key)
      sub(/\][ \t]*=.*/, "", key)
      return trim(key)
    }
    if (key ~ /^\[[\"\047].*[\"\047]\][ \t]*=/) {
      sub(/^\[[\"\047]/, "", key)
      sub(/[\"\047]\][ \t]*=.*/, "", key)
      gsub(/\\\\/, "\\", key)
      gsub(/\\\"/, "\"", key)
      gsub(/\\\047/, "\047", key)
      return trim(key)
    }
    return ""
  }
  function lua_split_inline(s,    i, ch, nxt, in_sq, in_dq, out, comment) {
    inline_comment=""
    in_sq=0
    in_dq=0
    out=""
    for (i=1; i<=length(s); i++) {
      ch=substr(s, i, 1)
      nxt=substr(s, i+1, 1)
      if (ch == "\"" && !in_sq && substr(s, i-1, 1) != "\\") {
        in_dq = !in_dq
      } else if (ch == "\047" && !in_dq && substr(s, i-1, 1) != "\\") {
        in_sq = !in_sq
      }
      if (!in_sq && !in_dq && ch == "-" && nxt == "-") {
        comment=substr(s, i + 2)
        inline_comment=trim(comment)
        return trim(out)
      }
      out = out ch
    }
    return trim(out)
  }
  BEGIN { in_table=0; depth=0; comment_block=""; current_group="" }
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
    code=lua_split_inline(line)
    inline=inline_comment
    if (!in_table) {
      if (code ~ /^return[ \t]*\{[ \t]*,?$/) {
        in_table=1
        depth=0
        current_group=""
        next
      }
      if (code ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*\{[ \t]*,?$/) {
        key=code
        sub(/^[ \t]*/, "", key)
        sub(/[ \t]*=.*$/, "", key)
        in_table=1
        depth=0
        current_group=key
        next
      }
      next
    }
    if (code ~ /^}[ \t]*,?[ \t]*$/) {
      if (depth == 0) {
        in_table=0
        current_group=""
      } else {
        depth--
        delete stack[depth+1]
      }
      next
    }
    key=lua_extract_key(code)
    if (key == "") next
    if (code ~ /=[ \t]*\{[ \t]*,?$/) {
      depth++
      stack[depth]=key
      next
    }
    if (code ~ /=/) {
      desc=""
      if (inline != "") desc=inline
      else if (comment_block != "") desc=comment_block
      path=join_path(key)
      n=split(path, parts, ".")
      path_token=""
      for (i=1; i<=n; i++) {
        if (path_token != "") path_token=path_token "_"
        path_token=path_token encode(parts[i])
      }
      env_new=docs_lua_prefix file_key
      if (current_group != "") env_new=env_new "__" current_group
      for (i=1; i<=n; i++) {
        env_new=env_new "__" parts[i]
      }
      env_new_root=env_new
      if (legacy_prefix == "LUA") env_legacy="LUA_" path_token
      else env_legacy=legacy_prefix "_" path_token
      if (current_group == "") env_legacy_root=env_legacy
      else if (legacy_prefix == "LUA") env_legacy_root="LUA_" encode(current_group) "_" path_token
      else env_legacy_root=legacy_prefix "_" encode(current_group) "_" path_token
      subgroup=path
      sub(/\..*$/, "", subgroup)
      print env_new "\t" file_key "\t" current_group "\t" subgroup "\t" source_id "\t" file "\t" desc "\t" env_legacy "\t" env_new_root "\t" env_legacy_root
      comment_block=""
    }
  }
  ' "${file}" >> "${lua_items_file}"
done <<< "${lua_files}"

collect_handcrafted_envs

handcrafted_rows_json="$(jq -R -s '
  split("\n")
  | map(select(length>0)
    | split("\t") as $parts
    | {
        name: ($parts[0] // ""),
        source_path: ($parts[1] // ""),
        group: ($parts[2] // ""),
        description: ($parts[3] // ""),
        source_id: (
          if ($parts[2] // "") == "args" then "hooks_args"
          elif ($parts[2] // "") == "hooks" then "hooks"
          elif ($parts[2] // "") == "vars" then "hooks_vars"
          else "hooks_misc"
          end
        )
      }
  )
  | map(select(.name != "" and .group != ""))
' "${handcrafted_file}")"

ini_rows_json="$(jq -R -s --argjson replacement_map "${replacement_map_json}" '
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {
        name: (.[7] // (.[0] // "")),
        file_key: (.[1] // ""),
        section: (.[2] // "INI"),
        source_id: (.[3] // ""),
        source_path: (.[4] // ""),
        description: (.[5] // ""),
        legacy_name: (.[6] // "")
      }
    | . as $row
    | .replaced_by = (
        [ $row.name, $row.legacy_name ]
        | map(select(length>0) | ($replacement_map[.] // []))
        | add
        | unique
      )
  )
' "${ini_items_file}")"

lua_rows_json="$(jq -R -s --argjson replacement_map "${replacement_map_json}" '
  split("\n")
  | map(select(length>0)
    | split("\t")
    | {
        name: (.[8] // (.[0] // "")),
        file_key: (.[1] // ""),
        group: (.[2] // ""),
        subgroup: (.[3] // ""),
        source_id: (.[4] // ""),
        source_path: (.[5] // ""),
        description: (.[6] // ""),
        legacy_name: (.[7] // ""),
        legacy_name_root: (.[9] // "")
      }
    | . as $row
    | .replaced_by = (
        [ $row.name, $row.legacy_name, $row.legacy_name_root ]
        | map(select(length>0) | ($replacement_map[.] // []))
        | add
        | unique
      )
  )
' "${lua_items_file}")"

warn_duplicate_generated_names() {
  local kind="$1"
  local rows_json="$2"
  jq -r --arg kind "${kind}" '
    group_by(.name)
    | map(select(length > 1))
    | sort_by(.[0].name)
    | .[]
    | "Warning: duplicate " + $kind + " generated env name " + .[0].name + " (occurrences=" + (length|tostring) + ")"
  ' <<< "${rows_json}" >&2 || true
}

count_duplicate_generated_names() {
  local rows_json="$1"
  jq -r '
    group_by(.name)
    | map(select(length > 1))
    | length
  ' <<< "${rows_json}" 2>/dev/null || echo 0
}

warn_duplicate_generated_names "INI" "${ini_rows_json}"
warn_duplicate_generated_names "LUA" "${lua_rows_json}"

if [ "${ENV_DOCS_FAIL_ON_DUPLICATES:-false}" = "true" ]; then
  ini_dup_count="$(count_duplicate_generated_names "${ini_rows_json}")"
  lua_dup_count="$(count_duplicate_generated_names "${lua_rows_json}")"
  if [ "${ini_dup_count}" -gt 0 ] || [ "${lua_dup_count}" -gt 0 ]; then
    echo "Error: duplicate generated env names found (INI=${ini_dup_count}, LUA=${lua_dup_count})." >&2
    echo "Set ENV_DOCS_FAIL_ON_DUPLICATES=false to keep warning-only behavior." >&2
    exit 1
  fi
fi

jq -n \
  --arg image_tag "${image_tag}" \
  --argjson handcrafted_rows "${handcrafted_rows_json}" \
  --argjson ini_rows "${ini_rows_json}" \
  --argjson lua_rows "${lua_rows_json}" \
  '
  def normalize_entries(rows):
    rows
    | group_by(.name)
    | map({
        name: .[0].name,
        description: ((map(select(.description != "") | .description) | first) // ""),
        source_ids: (map(.source_id) | map(select(length > 0)) | unique),
        replaced_by: (map(.replaced_by // []) | add | unique)
      })
    | sort_by(.name);

  def by_section(rows):
    rows
    | group_by(.section)
    | map({ (.[0].section): (normalize_entries(.)) })
    | add;

  def by_subgroup(rows):
    rows
    | group_by(.subgroup)
    | map({ (.[0].subgroup): (normalize_entries(.)) })
    | add;

  def by_group(rows):
    rows
    | group_by(.group)
    | map({ (.[0].group): (by_subgroup(.)) })
    | add;

  def lua_file_groups(rows):
    (rows | map(.group) | unique) as $all_groups
    | (rows | map(select(.group != "") | .group) | unique) as $named_groups
    | if (($all_groups | length) == 1 and ($named_groups | length) == 1)
      then by_subgroup(rows)
      else by_group(rows)
      end;

  def as_source_map(rows):
    rows
    | map({key: .source_id, value: .source_path})
    | map(select(.key != "" and .value != ""))
    | unique_by(.key)
    | from_entries;

  $ini_rows as $ini_rows_resolved
  | $lua_rows as $lua_rows_resolved
  | {
    image_tag: $image_tag,
    meta: {
      sources: (
        ({hooks_args:"scripts/env_hooks/args", hooks:"scripts/env_hooks", hooks_vars:"scripts/env_hooks/vars"})
        + as_source_map($ini_rows_resolved)
        + as_source_map($lua_rows_resolved)
      )
    },
    env: {
      custom: {
        args: normalize_entries($handcrafted_rows | map(select(.group == "args"))),
        hooks: normalize_entries($handcrafted_rows | map(select(.group == "hooks"))),
        vars: normalize_entries($handcrafted_rows | map(select(.group == "vars")))
      },
      generated: {
        ini: (
          $ini_rows_resolved
          | group_by(.file_key)
          | map({ (.[0].file_key): (by_section(.)) })
          | add
        ),
        lua: (
          $lua_rows_resolved
          | group_by(.file_key)
          | map({ (.[0].file_key): (lua_file_groups(.)) })
          | add
        )
      }
    }
  }' > "${output_path}"

bash "${repo_root}/scripts/generate_env_index.sh" "$(dirname "${output_path}")" "$(dirname "${output_path}")/index.json"
