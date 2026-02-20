DESCRIPTION="Workshop IDs and collections; replaces INI_WorkshopItems."
REPLACES="ini__pzserver__WorkshopItems"

manual_apply() {
	# Resolve all WORKSHOP_IDS (collections and direct mod IDs) to a flat list of mod IDs
	if [ -n "${WORKSHOP_IDS:-}" ]; then
		echo "*** INFO: Resolving Workshop IDs and Collections: ${WORKSHOP_IDS} ***"
		if [ -x /server/scripts/resolve_workshop_collection.sh ]; then
			resolved_ids=$( /server/scripts/resolve_workshop_collection.sh "${WORKSHOP_IDS}" )
			resolver_status=$?
			if [ $resolver_status -ne 0 ] || [ -z "$resolved_ids" ]; then
				echo "Warning: failed to resolve Workshop collections, leaving WorkshopItems unchanged." >&2
				workshop_resolve_failed=true
			else
				# Join with semicolon for ini
				resolved_ids_str=$(echo "$resolved_ids" | paste -sd ';' -)
				workshop_ids_effective="${resolved_ids_str}"
				set_ini_override "WorkshopItems" "${resolved_ids_str}"
				echo "*** INFO: WorkshopItems resolved to: ${resolved_ids_str} ***"
			fi
		else
			echo "Warning: resolve_workshop_collection.sh not found or not executable, leaving WorkshopItems unchanged." >&2
			workshop_resolve_failed=true
		fi
	else
		echo "*** INFO: WORKSHOP_IDS is empty, clearing configuration ***"
		set_ini_override "WorkshopItems" ""
	fi
}
