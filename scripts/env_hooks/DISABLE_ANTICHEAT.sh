DESCRIPTION="Disable AntiCheatProtectionType entries by index or ranges."
REPLACES=""

manual_apply() {
  if [ -n "${DISABLE_ANTICHEAT:-}" ]; then
    IFS=',' read -ra ITEMS <<< "${DISABLE_ANTICHEAT}"
    for ITEM in "${ITEMS[@]}"; do
      if [[ "$ITEM" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        START=${BASH_REMATCH[1]}
        END=${BASH_REMATCH[2]}
        for ((i=START; i<=END; i++)); do
          set_ini_override "AntiCheatProtectionType${i}" "false"
        done
      elif [[ "$ITEM" =~ ^[0-9]+$ ]]; then
        set_ini_override "AntiCheatProtectionType${ITEM}" "false"
      fi
    done
  fi
}
