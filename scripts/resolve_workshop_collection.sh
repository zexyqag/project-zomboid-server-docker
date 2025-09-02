#!/bin/bash

# Usage: resolve_workshop_collection.sh <id1>[;<id2>...] [depth_limit]
# Requires: curl, jq, STEAM_API_KEY env var (optional for public collections)

IDS_RAW="$1"
DEPTH_LIMIT="${2:-3}"
STEAM_API_KEY="${STEAM_API_KEY}"

if [ -z "$IDS_RAW" ]; then
  echo "Usage: $0 <id1>[;<id2>...] [depth_limit] (STEAM_API_KEY env optional for public collections)" >&2
  exit 1
fi

# Split input IDs by semicolon
IFS=';' read -ra IDS <<< "$IDS_RAW"

declare -A VISITED
declare -A MODS

depth=1
to_process=("${IDS[@]}")

while (( depth <= DEPTH_LIMIT )) && ((${#to_process[@]} > 0)); do
  # Prepare POST data for batch query
  post_data="collectioncount=${#to_process[@]}"
  for i in "${!to_process[@]}"; do
    post_data+="&publishedfileids[$i]=${to_process[$i]}"
  done
  if [ -n "$STEAM_API_KEY" ]; then
    post_data+="&key=$STEAM_API_KEY"
  fi
  resp=$(curl -s -X POST 'https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/' \
    --data "$post_data")
  # Next batch of collections to process
  next_batch=()
  count=$(echo "$resp" | jq '.response.resultcount')
  for ((idx=0; idx<count; idx++)); do
    # Mark as visited
    id=$(echo "$resp" | jq -r ".response.collectiondetails[$idx].publishedfileid")
    VISITED[$id]=1
    # Get children
    children=$(echo "$resp" | jq -c ".response.collectiondetails[$idx].children[]?")
    for child in $children; do
      child_id=$(echo "$child" | jq -r '.publishedfileid')
      child_type=$(echo "$child" | jq -r '.filetype')
      if [ "$child_type" == "0" ]; then
        MODS[$child_id]=1
      elif [ "$child_type" == "2" ]; then
        # Only add if not visited
        if [ -z "${VISITED[$child_id]}" ]; then
          next_batch+=("$child_id")
        fi
      fi
    done
  done
  to_process=("${next_batch[@]}")
  ((depth++))
done

# Output unique Workshop IDs (mods)
for mid in "${!MODS[@]}"; do
  echo "$mid"
done | sort -u
