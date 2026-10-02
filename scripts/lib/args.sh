#!/bin/bash
# Builds the start-server.sh argument list: JVM options, `--`, then server options.

build_server_args() {
  # $1 = admin password ("" once the server database exists)
  local admin_password="$1"
  ARGS=()
  if [ -n "${MEMORY:-}" ]; then
    ARGS+=("-Xms${MEMORY}" "-Xmx${MEMORY}")
  fi
  is_true "${SOFTRESET:-}" && ARGS+=(-Dsoftreset)
  ARGS+=(--)

  is_true "${COOP:-}" && ARGS+=(-coop)
  is_true "${NOSTEAM:-}" && ARGS+=(-nosteam)
  [ -n "${CACHEDIR:-}" ] && ARGS+=("-cachedir=${CACHEDIR}")
  [ -n "${MODFOLDERS:-}" ] && ARGS+=(-modfolders "${MODFOLDERS}")
  is_true "${DEBUG:-}" && ARGS+=(-debug)
  [ -n "${ADMINUSERNAME:-}" ] && ARGS+=(-adminusername "${ADMINUSERNAME}")
  ARGS+=(-servername "${SERVERNAME}")

  [ -n "${IP:-}" ] && ARGS+=(-ip "${IP}")
  [ -n "${PORT:-}" ] && ARGS+=(-port "${PORT}")
  [ -n "${UDPPORT:-}" ] && ARGS+=(-udpport "${UDPPORT}")
  [ -n "${STEAMPORT1:-}" ] && ARGS+=(-steamport1 "${STEAMPORT1}")
  [ -n "${STEAMPORT2:-}" ] && ARGS+=(-steamport2 "${STEAMPORT2}")
  local vac="${STEAMVAC:-}"
  case "${vac,,}" in
    true|false) ARGS+=(-steamvac "${vac,,}") ;;
  esac
  [ -n "${admin_password}" ] && ARGS+=(-adminpassword "${admin_password}")
  return 0
}
