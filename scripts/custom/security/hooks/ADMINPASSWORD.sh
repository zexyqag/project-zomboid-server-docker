DESCRIPTION="Admin password, used when the server creates its database on first start."
REPLACES=""
DEPENDS_ON="ARGS_SERVER_END"

manual_apply() {
  local value
  value="$(read_secret ADMINPASSWORD ADMINPASSWORD_FILE)"
  # Only passed until the database holding the admin account exists, to keep it out of later launch lines.
  if [ -n "${value}" ] && [ ! -f "${HOMEDIR}/Zomboid/db/${SERVERNAME}.db" ]; then
    ARGS+=(-adminpassword "${value}")
  fi
}
