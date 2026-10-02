#!/bin/bash

set -euo pipefail

PZ_URL_WEB="https://projectzomboid.com/blog/"
PZ_URL_FORUM="https://theindiestone.com/forums/forum/35-pz-updates/"
USER_AGENT="pz-server-version-check/1.0"

fetch_url() {
  local url="$1"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 20 \
    -H "User-Agent: ${USER_AGENT}" "${url}" 2>/dev/null || true
}

max_version() {
  sed '/^$/d' | sort -V | tail -n1
}

# Every lookup can legitimately match nothing, which must not abort the script under pipefail.
forum_versions() {
  echo "${FORUM_DATA}" | grep -oPi "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})? ($1)" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" || true
}

web_version() {
  echo "${WEBPAGE_DATA}" | grep -oiE "$1[^0-9]*[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?" | head -n1 | grep -oE "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?" || true
}

FORUM_DATA=$(fetch_url "${PZ_URL_FORUM}")
WEBPAGE_DATA=$(fetch_url "${PZ_URL_WEB}")

LATEST_FORUM_STABLE_VERSION=$(forum_versions "STABLE" | max_version)
LATEST_FORUM_UNSTABLE_VERSION=$(forum_versions "BETA|HOTFIX|UNSTABLE" | max_version)
LATEST_WEBPAGE_STABLE_VERSION=$(web_version "Stable Build")
LATEST_WEBPAGE_UNSTABLE_VERSION=$(web_version "IWBUMS Beta")

LATEST_STABLE_VERSION=$(printf '%s\n' "${LATEST_FORUM_STABLE_VERSION}" "${LATEST_WEBPAGE_STABLE_VERSION}" | max_version)
LATEST_UNSTABLE_VERSION=$(printf '%s\n' "${LATEST_FORUM_UNSTABLE_VERSION}" "${LATEST_WEBPAGE_UNSTABLE_VERSION}" | max_version)

# The forum and blog keep reporting an unstable version after a beta closes, and it then
# matches the stable one. Steam has no beta branch in that case, so report none.
if [ -n "${LATEST_UNSTABLE_VERSION}" ] \
  && [ "$(printf '%s\n' "${LATEST_STABLE_VERSION}" "${LATEST_UNSTABLE_VERSION}" | max_version)" = "${LATEST_STABLE_VERSION}" ]; then
  LATEST_UNSTABLE_VERSION=""
fi

if [ -z "${LATEST_STABLE_VERSION}" ]; then
  echo "Error: failed to detect latest Project Zomboid versions" >&2
  echo "Stable forum: ${LATEST_FORUM_STABLE_VERSION:-<none>}, stable web: ${LATEST_WEBPAGE_STABLE_VERSION:-<none>}" >&2
  echo "Unstable forum: ${LATEST_FORUM_UNSTABLE_VERSION:-<none>}, unstable web: ${LATEST_WEBPAGE_UNSTABLE_VERSION:-<none>}" >&2
  exit 2
fi

echo "LATEST_STABLE_VERSION=${LATEST_STABLE_VERSION}"
echo "LATEST_UNSTABLE_VERSION=${LATEST_UNSTABLE_VERSION}"
