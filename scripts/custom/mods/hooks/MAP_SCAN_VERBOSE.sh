DESCRIPTION="Verbose output while scanning workshop maps."
REPLACES=""
DEPENDS_ON="WORKSHOP_IDS"

manual_apply() {
  # Fixes EOL in script file for good measure
  sed -i 's/\r$//' /server/scripts/search_folder.sh
  # Check 'search_folder.sh' script for details
  if [ -e "${HOMEDIR}/pz-dedicated/steamapps/workshop/content/108600" ]; then

    map_list=""
    source /server/scripts/search_folder.sh "${HOMEDIR}/pz-dedicated/steamapps/workshop/content/108600"
    if [ -f "${HOMEDIR}/maps.txt" ]; then
      map_list=$(<"${HOMEDIR}/maps.txt")
      rm "${HOMEDIR}/maps.txt"
    fi

    if [ -n "${map_list}" ]; then
      echo "*** INFO: Added maps including ${map_list} ***"
      set_ini_override "Map" "${map_list}Muldraugh, KY"

      # Checks which added maps have spawnpoints.lua files and adds them to the spawnregions file if they aren't already added
      IFS=";" read -ra strings <<< "$map_list"
      for string in "${strings[@]}"; do
          if [ -f "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_spawnregions.lua" ] && ! grep -q "$string" "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_spawnregions.lua"; then
            if [ -e "${HOMEDIR}/pz-dedicated/media/maps/$string/spawnpoints.lua" ]; then
              result="{ name = \"$string\", file = \"media/maps/$string/spawnpoints.lua\" },"
              sed -i "/function SpawnRegions()/,/return {/ {    /return {/ a\
              \\t\\t$result
              }" "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_spawnregions.lua"
            fi
          elif [ ! -f "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_spawnregions.lua" ]; then
            echo "Warning: spawnregions file not found, skipping spawnpoints update" >&2
          fi
      done
    fi 
  fi
}
