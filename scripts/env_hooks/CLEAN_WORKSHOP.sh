DESCRIPTION="Clean unused workshop content for resolved WORKSHOP_IDS."
REPLACES=""
DEPENDS_ON="WORKSHOP_IDS"

manual_apply() {
  # Optional cleanup of unused workshop content
  if is_true "${CLEAN_WORKSHOP:-}" && [ -n "${WORKSHOP_IDS:-}" ] && [ -n "${workshop_ids_effective:-}" ] && [ "${workshop_resolve_failed:-}" != "true" ]; then
    workshop_dir="${HOMEDIR}/pz-dedicated/steamapps/workshop/content/108600"
    if [ -d "${workshop_dir}" ]; then
      if is_true "${CLEAN_WORKSHOP_DRY_RUN:-}"; then
        echo "*** INFO: CLEAN_WORKSHOP_DRY_RUN enabled, listing unused workshop items ***"
      else
        echo "*** INFO: CLEAN_WORKSHOP enabled, pruning unused workshop items ***"
      fi
      IFS=';' read -ra KEEP_IDS <<< "${workshop_ids_effective}"
      keep_total=${#KEEP_IDS[@]}

      if [ -n "${CLEAN_WORKSHOP_KEEP_FILE:-}" ]; then
        mkdir -p "$(dirname "${CLEAN_WORKSHOP_KEEP_FILE}")"
        printf '%s\n' "${KEEP_IDS[@]}" > "${CLEAN_WORKSHOP_KEEP_FILE}"
        echo "*** INFO: Wrote workshop keep list to ${CLEAN_WORKSHOP_KEEP_FILE} ***"
      fi

      total_items=0
      keep_found=0
      for item_dir in "${workshop_dir}"/*; do
        [ -d "${item_dir}" ] || continue
        total_items=$((total_items + 1))
        item_id=$(basename "${item_dir}")
        for keep_id in "${KEEP_IDS[@]}"; do
          if [ "${item_id}" == "${keep_id}" ]; then
            keep_found=$((keep_found + 1))
            break
          fi
        done
      done
      if [ "${total_items}" -gt 0 ] && [ "${keep_found}" -eq 0 ] && ! is_true "${CLEAN_WORKSHOP_ALLOW_REMOVE_ALL:-}"; then
        echo "Warning: CLEAN_WORKSHOP would remove all workshop items; set CLEAN_WORKSHOP_ALLOW_REMOVE_ALL=true to allow." >&2
      else
        if [ "${keep_found}" -lt "${keep_total}" ]; then
          echo "Warning: Some keep IDs were not found on disk (${keep_found}/${keep_total})." >&2
        fi
        removed_count=0
        for item_dir in "${workshop_dir}"/*; do
          [ -d "${item_dir}" ] || continue
          item_id=$(basename "${item_dir}")
          keep=false
          for keep_id in "${KEEP_IDS[@]}"; do
            if [ "${item_id}" == "${keep_id}" ]; then
              keep=true
              break
            fi
          done
          if [ "${keep}" == "false" ]; then
            if is_true "${CLEAN_WORKSHOP_DRY_RUN:-}"; then
              echo "*** INFO: Would remove unused workshop item ${item_id} ***"
            else
              echo "*** INFO: Removing unused workshop item ${item_id} ***"
              rm -rf "${item_dir}"
            fi
            removed_count=$((removed_count + 1))
          fi
        done
        echo "*** INFO: Workshop cleanup summary: kept ${keep_found}/${total_items}, removed ${removed_count} ***"
      fi
    fi
  fi
}
