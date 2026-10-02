#!/bin/bash
# Workshop items and the maps that enabled mods bring along.

VANILLA_MAP="Muldraugh, KY"

apply_workshop_ids() {
  # $1 = INI file. Collections in WORKSHOP_IDS are expanded to the items they contain.
  local ini_file="$1" resolved
  [ -n "${WORKSHOP_IDS+x}" ] || return 0
  if [ -z "${WORKSHOP_IDS}" ]; then
    set_ini_value "${ini_file}" WorkshopItems ""
    return 0
  fi
  if ! resolved="$(bash "${SCRIPT_DIR}/resolve_workshop_collection.sh" "${WORKSHOP_IDS}")" || [ -z "${resolved}" ]; then
    echo "Warning: could not resolve WORKSHOP_IDS through the Steam API, leaving WorkshopItems unchanged." >&2
    return 0
  fi
  resolved="$(paste -sd ';' <<< "${resolved}")"
  set_ini_value "${ini_file}" WorkshopItems "${resolved}"
  echo "Config: WorkshopItems set to ${resolved}"
}

enabled_mod_ids() {
  # $1 = INI file; one mod ID per line. B42 entries look like `\ModId` or `<workshop id>\ModId`.
  ini_value "$1" Mods | tr ';' '\n' | sed -e 's/.*\\//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d'
}

mod_maps() {
  # $1 = workshop content dir, $2 = file of enabled mod IDs.
  # Prints "<enabled|disabled>\t<map name>\t<map dir>" for each map of a downloaded mod. B41 mods
  # keep files in mods/<mod>/, B42 mods in versioned folders such as mods/<mod>/42/ and mods/<mod>/common/.
  local content_dir="$1" enabled_file="$2" mod_dir info id state map_dir
  for mod_dir in "${content_dir}"/*/mods/*/; do
    [ -d "${mod_dir}" ] || continue
    id=""
    for info in "${mod_dir}mod.info" "${mod_dir}"*/mod.info; do
      [ -f "${info}" ] || continue
      id="$(sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*//p' "${info}" | tr -d '\r' | head -n 1)"
      [ -n "${id}" ] && break
    done
    [ -n "${id}" ] || continue
    state=disabled
    grep -qxF "${id}" "${enabled_file}" && state=enabled
    for map_dir in "${mod_dir}"media/maps/*/ "${mod_dir}"*/media/maps/*/; do
      # Mods that patch the vanilla map ship a folder with its name; it's always in Map= anyway.
      [ -d "${map_dir}" ] && [ "$(basename "${map_dir}")" != "${VANILLA_MAP}" ] || continue
      printf '%s\t%s\t%s\n' "${state}" "$(basename "${map_dir}")" "${map_dir%/}"
    done
  done
}

merge_map_list() {
  # $1 = current Map= value, $2 = ';'-separated maps to drop, then the maps to add. Keeps the
  # admin's order, adds new maps before the vanilla map and keeps the vanilla map last.
  local current="$1" name vanilla=false
  local -a merged=() entries=() dropped=()
  local -A present=()
  IFS=';' read -ra dropped <<< "$2"
  shift 2
  for name in "${dropped[@]}"; do
    present["${name}"]=1
  done
  IFS=';' read -ra entries <<< "${current}"
  for name in "${entries[@]}"; do
    [ -n "${name}" ] || continue
    if [ "${name}" = "${VANILLA_MAP}" ]; then
      vanilla=true
      continue
    fi
    [ -n "${present[${name}]+x}" ] && continue
    present["${name}"]=1
    merged+=("${name}")
  done
  for name in "$@"; do
    [ -n "${present[${name}]+x}" ] && continue
    present["${name}"]=1
    merged+=("${name}")
  done
  if [ "${vanilla}" = true ] || [ -z "${current}" ]; then
    merged+=("${VANILLA_MAP}")
  fi
  (IFS=';'; printf '%s' "${merged[*]}")
}

add_spawn_region() {
  # $1 = spawnregions file, $2 = map name. Adds the map's spawn points when they are missing.
  local file="$1" name="$2"
  grep -qF "media/maps/${name}/spawnpoints.lua" "${file}" && return 0
  NAME="${name}" awk '
    { print }
    !done && /^[[:space:]]*return[[:space:]]*\{/ {
      printf "\t\t{ name = \"%s\", file = \"media/maps/%s/spawnpoints.lua\" },\n", ENVIRON["NAME"], ENVIRON["NAME"]
      done = 1
    }
  ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
  echo "Config: spawn region added for ${name}"
}

remove_spawn_region() {
  # $1 = spawnregions file, $2 = map name
  local file="$1" name="$2"
  grep -qF "media/maps/${name}/spawnpoints.lua" "${file}" || return 0
  grep -vF "media/maps/${name}/spawnpoints.lua" "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
  echo "Config: spawn region removed for ${name}"
}

# Adds the maps of enabled mods to Map= and their spawn points to the spawnregions file, and
# removes the maps of downloaded mods that are no longer enabled, which the server can't load.
apply_mod_maps() {
  # $1 = INI file, $2 = spawnregions file, $3 = workshop content dir
  local ini_file="$1" spawn_file="$2" content_dir="$3" enabled maps current merged state name dir
  [ -d "${content_dir}" ] || return 0
  enabled="$(mktemp)"
  enabled_mod_ids "${ini_file}" > "${enabled}"
  maps="$(mod_maps "${content_dir}" "${enabled}")"
  rm -f "${enabled}"
  [ -n "${maps}" ] || return 0

  local -a added=() dropped=()
  local -A enabled_map=()
  while IFS=$'\t' read -r state name dir; do
    if [ "${state}" = enabled ]; then
      added+=("${name}")
      enabled_map["${name}"]=1
    fi
  done <<< "${maps}"
  while IFS=$'\t' read -r state name dir; do
    [ "${state}" = disabled ] && [ -z "${enabled_map[${name}]+x}" ] && dropped+=("${name}")
  done <<< "${maps}"

  current="$(ini_value "${ini_file}" Map)"
  merged="$(merge_map_list "${current}" "$(IFS=';'; printf '%s' "${dropped[*]}")" "${added[@]}")"
  if [ "${merged}" != "${current}" ]; then
    set_ini_value "${ini_file}" Map "${merged}"
    echo "Config: Map set to ${merged}"
  fi

  [ -f "${spawn_file}" ] || return 0
  while IFS=$'\t' read -r state name dir; do
    if [ -n "${enabled_map[${name}]+x}" ]; then
      [ -f "${dir}/spawnpoints.lua" ] && add_spawn_region "${spawn_file}" "${name}"
    else
      remove_spawn_region "${spawn_file}" "${name}"
    fi
  done <<< "${maps}"
  return 0
}
