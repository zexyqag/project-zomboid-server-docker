#!/bin/bash

set -euo pipefail

docs_dir="${1:-docs/env}"
output_path="${2:-${docs_dir}/index.json}"
output_name="$(basename "${output_path}")"

mkdir -p "$(dirname "${output_path}")"

files_json="$(
  find "${docs_dir}" -maxdepth 1 -type f -name '*.json' ! -name "${output_name}" -print | sort \
    | while IFS= read -r file; do
        [ -z "${file}" ] && continue
        file_name="$(basename "${file}")"
        image_tag="$(jq -r '.image_tag // ""' "${file}" 2>/dev/null || echo "")"
        jq -cn --arg file "${file_name}" --arg image_tag "${image_tag}" '{file:$file,image_tag:$image_tag}'
      done \
    | jq -s 'sort_by(.file)'
)"

jq -n --argjson files "${files_json}" '{files:$files}' > "${output_path}"
