DESCRIPTION="Mod IDs for the server; replaces ini__pzserver__Mods."
REPLACES="ini__pzserver__Mods"

manual_apply() {
	if [ -n "${MOD_IDS:-}" ]; then
		echo "*** INFO: Found Mods including ${MOD_IDS} ***"
		set_ini_value "Mods" "${MOD_IDS}"
	else
		echo "*** INFO: MOD_IDS is empty, clearing configuration ***"
		set_ini_value "Mods" ""
	fi
}
