DESCRIPTION="Force update the server before launch."
REPLACES=""

manual_apply() {
  if is_true "${FORCEUPDATE:-}"; then
    echo "FORCEUPDATE variable is set, so the server will be updated right now"
    local beta_args=()
    if [ "${STEAMAPPBRANCH}" != "public" ]; then
      beta_args=(-beta "${STEAMAPPBRANCH}")
    fi
    bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" +login anonymous +app_update "${STEAMAPPID}" "${beta_args[@]}" validate +quit
  fi
}
