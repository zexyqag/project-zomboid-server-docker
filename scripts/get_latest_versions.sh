#!/bin/bash

set -euo pipefail

PZ_URL_WEB="https://projectzomboid.com/blog/"
PZ_URL_FORUM="https://theindiestone.com/forums/index.php?/forum/35-pz-updates/"
STEAM_API_KEY="${STEAM_API_KEY:-}"
STEAM_APP_ID=380870

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
## Try Steam Web API (build IDs)        ##
##                                      ##
##########################################
if [ -n "${STEAM_API_KEY}" ]; then
  STEAM_API_RESP=$(curl -s "https://api.steampowered.com/ISteamApps/GetAppInfo/v2/?appids=${STEAM_APP_ID}&key=${STEAM_API_KEY}")
  STEAM_STABLE_BUILD=$(echo "${STEAM_API_RESP}" | jq -r ".appdata[\"${STEAM_APP_ID}\"].depots.branches.public.buildid // empty")
  STEAM_UNSTABLE_BUILD=$(echo "${STEAM_API_RESP}" | jq -r ".appdata[\"${STEAM_APP_ID}\"].depots.branches.unstable.buildid // empty")

  if [ -n "${STEAM_STABLE_BUILD}" ] && [ -n "${STEAM_UNSTABLE_BUILD}" ]; then
    echo "LATEST_STABLE_VERSION=${STEAM_STABLE_BUILD}"
    echo "LATEST_UNSTABLE_VERSION=${STEAM_UNSTABLE_BUILD}"
    exit 0
  else
    echo "Warning: Steam API did not return build IDs, falling back to forum/blog parsing" >&2
  fi
fi

##########################################
##                                      ##
## Checking the latest version in Forum ##
##                                      ##
##########################################
STABLE_TITLES="Released"
UNSTABLE_TITLES="BETA|HOTFIX|UNSTABLE"
FORUM_DATA=`curl -s "${PZ_URL_FORUM}"`

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
WEBPAGE_DATA=`curl "${PZ_URL_WEB}" 2>/dev/null`
LATEST_WEBPAGE_STABLE_VERSION=`echo "${WEBPAGE_DATA}" | grep -i "${STABLE_TEXT}" | head -n1 | cut -d ":" -f2 | awk '{print $1}'`
LATEST_WEBPAGE_UNSTABLE_VERSION=`echo "${WEBPAGE_DATA}" | grep -i "${UNSTABLE_TEXT}" | head -n1 | cut -d ":" -f2 | awk '{print $1}'`

LATEST_STABLE_VERSION=""
LATEST_STABLE_VERSION_COMPARE=$(versionCompare ${LATEST_FORUM_STABLE_VERSION} ${LATEST_WEBPAGE_STABLE_VERSION})
if [ $LATEST_STABLE_VERSION_COMPARE == -1 ]; then
  LATEST_STABLE_VERSION=$LATEST_WEBPAGE_STABLE_VERSION
else
  LATEST_STABLE_VERSION=$LATEST_FORUM_STABLE_VERSION
fi

LATEST_UNSTABLE_VERSION=""
LATEST_UNSTABLE_VERSION_COMPARE=$(versionCompare ${LATEST_FORUM_UNSTABLE_VERSION} ${LATEST_WEBPAGE_UNSTABLE_VERSION})
if [ $LATEST_UNSTABLE_VERSION_COMPARE == -1 ]; then
  LATEST_UNSTABLE_VERSION=$LATEST_WEBPAGE_UNSTABLE_VERSION
else
  LATEST_UNSTABLE_VERSION=$LATEST_FORUM_UNSTABLE_VERSION
fi

if [ -z "$LATEST_STABLE_VERSION" ] || [ -z "$LATEST_UNSTABLE_VERSION" ]; then
  echo "Error: failed to detect latest Project Zomboid versions" >&2
  exit 2
fi

echo "LATEST_STABLE_VERSION=${LATEST_STABLE_VERSION}"
echo "LATEST_UNSTABLE_VERSION=${LATEST_UNSTABLE_VERSION}"
