DESCRIPTION="Admin password for first setup; updates INI_Password if changed."
REPLACES="INI_Password"
DEPENDS_ON="ARGS_SERVER"

manual_apply() {
  local admin_value=""

  if [ -n "${ADMINPASSWORD_FILE:-}" ]; then
    if [ -f "${ADMINPASSWORD_FILE}" ]; then
      admin_value=$(<"${ADMINPASSWORD_FILE}")
    else
      echo "Warning: ADMINPASSWORD_FILE is set but file not found: ${ADMINPASSWORD_FILE}" >&2
    fi
  fi
  if [ -z "${admin_value}" ] && [ -n "${ADMINPASSWORD:-}" ]; then
    admin_value="${ADMINPASSWORD}"
  fi

  if [ -n "${admin_value}" ]; then
    if [ ! -f "${INI_FILE}" ]; then
      ARGS="${ARGS} -adminpassword ${admin_value}"
      echo "*** INFO: Setting admin password via -adminpassword (first setup) ***"
    else
      if [ -n "${PASSWORD:-}" ] || [ -n "${PASSWORD_FILE:-}" ]; then
        return
      fi
      safe_update_ini_key "${INI_FILE}" "Password" "ADMINPASSWORD" "ADMINPASSWORD_FILE"
    fi
  fi
}
