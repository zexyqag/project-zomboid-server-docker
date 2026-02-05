#!/bin/bash

set -euo pipefail

PZ_URL_WEB="https://projectzomboid.com/blog/"
PZ_URL_FORUM="https://theindiestone.com/forums/index.php?/forum/35-pz-updates/"
USER_AGENT="pz-server-version-check/1.0"
CACHE_FILE="${PZ_VERSION_CACHE_FILE:-/tmp/pz_versions.env}"

fetch_url() {
  local url="$1"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 20 \
    -H "User-Agent: ${USER_AGENT}" "${url}" 2>/dev/null || true
}

###########################################
##
## Function to compare two version numbers
##
## Return:
##   1: First version is higher
##  -1: Second version is higher
##   0: Both versions are equal
##
function versionCompare(){
  A_LENGTH=`echo -n $1|sed 's/[^\.]*//g'|wc -m`
  B_LENGTH=`echo -n $2|sed 's/[^\.]*//g'|wc -m`

  REVERSE=0
  A=""
  B=""

  if [ ${B_LENGTH} -gt ${A_LENGTH} ]; then
    A=$2
    B=$1
    REVERSE=1
  else
    A=$1
    B=$2
  fi

  CURRENT=1
  A_NUM=`echo -n $A|cut -d "." -f${CURRENT}`

  while [ "${A_NUM}" != "" ]; do
    B_NUM=`echo -n $B|cut -d "." -f${CURRENT}`

    if [ "$B_NUM" == "" ] || [ $A_NUM -gt $B_NUM ]; then
      if [ $REVERSE == 1 ]; then echo -1; else echo 1; fi
      return 0;
    elif [ $B_NUM -gt $A_NUM ]; then
      if [ $REVERSE == 1 ]; then echo 1; else echo -1; fi
      return 0;
    fi

    CURRENT=$((${CURRENT} + 1))
    A_NUM=`echo -n $A|cut -d "." -f${CURRENT}`
  done
  echo 0
}

##########################################
##                                      ##
## Forum/blog parsing                    ##
##                                      ##
##########################################

##########################################
##                                      ##
## Checking the latest version in Forum ##
##                                      ##
##########################################
STABLE_TITLES="Released"
UNSTABLE_TITLES="BETA|HOTFIX|UNSTABLE"
FORUM_DATA=`curl -s "${PZ_URL_FORUM}"`
FORUM_DATA=$(fetch_url "${PZ_URL_FORUM}")

LATEST_FORUM_STABLE_VERSIONS=$(echo "${FORUM_DATA}" | \
  grep -oPi "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})? ($STABLE_TITLES)" | \
  grep -oE "[0-9]+\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+" | sort | uniq)

LATEST_FORUM_UNSTABLE_VERSIONS=$(echo "${FORUM_DATA}" | \
  grep -oPi "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})? ($UNSTABLE_TITLES)" | \
  grep -oE "[0-9]+\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+" | sort | uniq)

LATEST_FORUM_STABLE_VERSION=0.0.0
for version in $LATEST_FORUM_STABLE_VERSIONS; do
  COMPARE_VERSION=$(versionCompare ${LATEST_FORUM_STABLE_VERSION} ${version})
  if [ $COMPARE_VERSION == -1 ]; then
    LATEST_FORUM_STABLE_VERSION=$version
  fi
done

LATEST_FORUM_UNSTABLE_VERSION=0.0.0
for version in $LATEST_FORUM_UNSTABLE_VERSIONS; do
  COMPARE_VERSION=$(versionCompare ${LATEST_FORUM_UNSTABLE_VERSION} ${version})
  if [ $COMPARE_VERSION == -1 ]; then
    LATEST_FORUM_UNSTABLE_VERSION=$version
  fi
done

################################################
##                                            ##
## Checking the latest version in the webpage ##
##                                            ##
################################################
STABLE_TEXT="Stable Build"
UNSTABLE_TEXT="IWBUMS Beta"
WEBPAGE_DATA=$(fetch_url "${PZ_URL_WEB}")
LATEST_WEBPAGE_STABLE_VERSION=$(echo "${WEBPAGE_DATA}" | grep -oiE "${STABLE_TEXT}[^0-9]*[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?" | head -n1 | grep -oE "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?")
LATEST_WEBPAGE_UNSTABLE_VERSION=$(echo "${WEBPAGE_DATA}" | grep -oiE "${UNSTABLE_TEXT}[^0-9]*[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?" | head -n1 | grep -oE "[0-9]{2,3}\.[0-9]{1,2}(\.[0-9]{1,2})?")

LATEST_STABLE_VERSION=""
if [ -n "${LATEST_FORUM_STABLE_VERSION}" ] && [ -n "${LATEST_WEBPAGE_STABLE_VERSION}" ]; then
  LATEST_STABLE_VERSION_COMPARE=$(versionCompare ${LATEST_FORUM_STABLE_VERSION} ${LATEST_WEBPAGE_STABLE_VERSION})
  if [ $LATEST_STABLE_VERSION_COMPARE == -1 ]; then
    LATEST_STABLE_VERSION=$LATEST_WEBPAGE_STABLE_VERSION
  else
    LATEST_STABLE_VERSION=$LATEST_FORUM_STABLE_VERSION
  fi
elif [ -n "${LATEST_FORUM_STABLE_VERSION}" ]; then
  LATEST_STABLE_VERSION=$LATEST_FORUM_STABLE_VERSION
elif [ -n "${LATEST_WEBPAGE_STABLE_VERSION}" ]; then
  LATEST_STABLE_VERSION=$LATEST_WEBPAGE_STABLE_VERSION
fi

LATEST_UNSTABLE_VERSION=""
if [ -n "${LATEST_FORUM_UNSTABLE_VERSION}" ] && [ -n "${LATEST_WEBPAGE_UNSTABLE_VERSION}" ]; then
  LATEST_UNSTABLE_VERSION_COMPARE=$(versionCompare ${LATEST_FORUM_UNSTABLE_VERSION} ${LATEST_WEBPAGE_UNSTABLE_VERSION})
  if [ $LATEST_UNSTABLE_VERSION_COMPARE == -1 ]; then
    LATEST_UNSTABLE_VERSION=$LATEST_WEBPAGE_UNSTABLE_VERSION
  else
    LATEST_UNSTABLE_VERSION=$LATEST_FORUM_UNSTABLE_VERSION
  fi
elif [ -n "${LATEST_FORUM_UNSTABLE_VERSION}" ]; then
  LATEST_UNSTABLE_VERSION=$LATEST_FORUM_UNSTABLE_VERSION
elif [ -n "${LATEST_WEBPAGE_UNSTABLE_VERSION}" ]; then
  LATEST_UNSTABLE_VERSION=$LATEST_WEBPAGE_UNSTABLE_VERSION
fi

if [ -z "${LATEST_STABLE_VERSION}" ] || [ -z "${LATEST_UNSTABLE_VERSION}" ]; then
  echo "Error: failed to detect latest Project Zomboid versions" >&2
  echo "Stable forum: ${LATEST_FORUM_STABLE_VERSION:-<none>}, stable web: ${LATEST_WEBPAGE_STABLE_VERSION:-<none>}" >&2
  echo "Unstable forum: ${LATEST_FORUM_UNSTABLE_VERSION:-<none>}, unstable web: ${LATEST_WEBPAGE_UNSTABLE_VERSION:-<none>}" >&2

  if [ -f "${CACHE_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${CACHE_FILE}"
    if [ -n "${LATEST_STABLE_VERSION:-}" ] && [ -n "${LATEST_UNSTABLE_VERSION:-}" ]; then
      echo "Warning: using cached Project Zomboid versions from ${CACHE_FILE}" >&2
    else
      exit 2
    fi
  else
    exit 2
  fi
fi

mkdir -p "$(dirname "${CACHE_FILE}")"
{
  echo "LATEST_STABLE_VERSION=${LATEST_STABLE_VERSION}"
  echo "LATEST_UNSTABLE_VERSION=${LATEST_UNSTABLE_VERSION}"
} > "${CACHE_FILE}"

echo "LATEST_STABLE_VERSION=${LATEST_STABLE_VERSION}"
echo "LATEST_UNSTABLE_VERSION=${LATEST_UNSTABLE_VERSION}"
