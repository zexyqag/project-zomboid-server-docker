#!/bin/bash
# Assembles the docs site: the page, the env references in <site>/env, and an index of them.
# References for earlier tags are copied from the live site, because each deploy replaces it.
# Usage: build_site.sh <site dir> <live site URL>

set -euo pipefail

site="$1"
base="$2"
env_dir="${site}/env"
mkdir -p "${env_dir}"
cp site/index.html "${site}/index.html"

live_index="$(mktemp)"
status="$(curl -sS -o "${live_index}" -w '%{http_code}' "${base}/env/index.json")"
case "${status}" in
  200)
    jq -r '.files[].file' "${live_index}" | grep -E '^[A-Za-z0-9._-]+\.json$' | while IFS= read -r file; do
      [ -f "${env_dir}/${file}" ] && continue
      curl -fsS -o "${env_dir}/${file}" "${base}/env/${file}"
      # References from before the env var redesign use another format and other names.
      jq -e '.vars' "${env_dir}/${file}" >/dev/null || rm "${env_dir}/${file}"
    done
    ;;
  404) echo "No published env references yet" ;;
  *) echo "Error: ${base}/env/index.json returned ${status}" >&2; exit 1 ;;
esac

find "${env_dir}" -maxdepth 1 -name '*.json' ! -name index.json -print0 | sort -z \
  | xargs -0 -r jq -c '{file: (input_filename | split("/") | last), image_tag}' \
  | jq -s '{files: .}' > "${env_dir}/index.json"
