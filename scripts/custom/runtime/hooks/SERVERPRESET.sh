DESCRIPTION="Preset name for SandboxVars; copies preset on first run or when SERVERPRESETREPLACE is true."
REPLACES=""

manual_apply() {
  # If preset is set, then the config file is generated when it doesn't exists or SERVERPRESETREPLACE is set to true.
  if [ -n "${SERVERPRESET:-}" ]; then
    # If preset file doesn't exists then show an error and exit
    if [ ! -f "${STEAMAPPDIR}/media/lua/shared/Sandbox/${SERVERPRESET}.lua" ]; then
      echo "*** ERROR: the preset ${SERVERPRESET} doesn't exists. Please fix the configuration before start the server ***"
      exit 1
    # If SandboxVars files doesn't exists or replace is true, copy the file
    elif [ ! -f "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua" ] || is_true "${SERVERPRESETREPLACE:-}"; then
      echo "*** INFO: New server will be created using the preset ${SERVERPRESET} ***"
      echo "*** Copying preset file from \"${STEAMAPPDIR}/media/lua/shared/Sandbox/${SERVERPRESET}.lua\" to \"${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua\" ***"
      mkdir -p "${HOMEDIR}/Zomboid/Server/"
      cp -nf "${STEAMAPPDIR}/media/lua/shared/Sandbox/${SERVERPRESET}.lua" "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua"
      sed -i "1s/return.*/SandboxVars = \{/" "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua"
      # Remove carriage return
      dos2unix "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua"
      # I have seen that the file is created in execution mode (755). Change the file mode for security reasons.
      chmod 644 "${HOMEDIR}/Zomboid/Server/${SERVERNAME}_SandboxVars.lua"
    fi
  fi
}
