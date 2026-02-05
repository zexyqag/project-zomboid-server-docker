#!/bin/bash

is_true() {
    local val="${1,,}"
    case "$val" in
        1|true|yes|y|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to recursively search for a folder name
search_folder() {
    local search_dir="$1"
    local counter=0
    local items=("$search_dir"/*)
    local total=${#items[@]}
    declare -A map_seen
    local map_names=()

    if [ "$total" -eq 0 ]; then
        return 0
    fi

    echo "Searching for maps in ${total} workshop item(s)..."

    for item in "${items[@]}"; do
        counter=$((counter + 1))
        if is_true "${MAP_SCAN_VERBOSE}"; then
            echo "Searching for maps: ($counter/$total)"
        fi

        # Check if the given directory exists
        if [ -d "$search_dir" ]; then                
            # Check if there is a "maps" folder within the "mods" directory
            if [ -d "$item/mods" ]; then
                for mod_folder in "$item/mods"/*; do
                    if [ -d "$mod_folder/media/maps" ]; then
                        # Copy maps to map folder if any are missing
                        map_dir="${HOMEDIR}/pz-dedicated/media/maps"
                        source_dirs=("$mod_folder/media/maps"/*)
                        need_copy=false
                        for source_dir in "${source_dirs[@]}"; do
                            [ -d "$source_dir" ] || continue
                            dir_name=$(basename "$source_dir")
                            if [ ! -d "$map_dir/$dir_name" ]; then
                                need_copy=true
                                break
                            fi
                        done
                        if [ "$need_copy" = "true" ]; then
                            if is_true "${MAP_SCAN_DRY_RUN}"; then
                                echo "Found map(s). Dry run enabled; skipping copy."
                            else
                                echo "Found map(s). Copying..."
                                cp -r "$mod_folder/media/maps"/* "${HOMEDIR}/pz-dedicated/media/maps"
                                echo "Successfully copied!"
                            fi
                        fi

                        # Collect unique map names across all mods.
                        for dir in "$mod_folder/media/maps"/*/; do
                            if [ -d "$dir" ]; then
                                dir_name=$(basename "$dir")
                                if [ -z "${map_seen[$dir_name]+x}" ]; then
                                    map_seen["$dir_name"]=1
                                    map_names+=("$dir_name")
                                fi
                            fi
                        done
                    fi
                done
            fi
        fi
    done

    if [ ${#map_names[@]} -gt 0 ]; then
        map_list=""
        for name in "${map_names[@]}"; do
            map_list+="$name;"
        done
        # Exports to .txt file to add to .ini file in entry.sh
        echo -n "$map_list" > "${HOMEDIR}/maps.txt"
    fi
}

parent_folder="$1"

if [ ! -d "$parent_folder" ]; then
    exit 1
fi

# Call the search_folder function with the provided arguments
search_folder "$parent_folder"