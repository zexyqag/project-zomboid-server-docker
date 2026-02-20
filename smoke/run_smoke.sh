#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

normalize_file() {
  local src="$1"
  local dst="$2"
  tr -d '\r' < "$src" > "$dst"
}

run_ini_dry_run() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export ini__sample__Public=true
    export ini__sample__PublicName="New Name"
    export ini__sample__Mods="ModA"
    export ini__sample__ServerOptions__PVP=false
    export ini__sample__ServerOptions__DropOffWhiteList=false
    export INI_CTRL_DRY_RUN=true
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini"
  )
  normalize_file "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.norm.ini"
  normalize_file "${TMP_DIR}/sample.ini" "${TMP_DIR}/sample.out.ini"
  if ! diff -u "${TMP_DIR}/sample.norm.ini" "${TMP_DIR}/sample.out.ini" >/dev/null; then
    echo "INI dry-run modified file" >&2
    exit 1
  fi
}

run_ini_load() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export ini__sample__Public=true
    export ini__sample__PublicName="New Name"
    export ini__sample__Mods="ModA"
    export ini__sample__ServerOptions__PVP=false
    export ini__sample__ServerOptions__DropOffWhiteList=false
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini"
  )
  normalize_file "${SCRIPT_DIR}/expected.ini" "${TMP_DIR}/expected.norm.ini"
  normalize_file "${TMP_DIR}/sample.ini" "${TMP_DIR}/sample.out.ini"
  diff -u "${TMP_DIR}/expected.norm.ini" "${TMP_DIR}/sample.out.ini" >/dev/null
}

run_ini_load_docs_style() {
  cp "${SCRIPT_DIR}/sample.ini" "${TMP_DIR}/sample.ini"
  (
    export ini__sample__Public=true
    export ini__sample__PublicName="New Name"
    export ini__sample__Mods="ModA"
    export ini__sample__ServerOptions__PVP=false
    export ini__sample__ServerOptions__DropOffWhiteList=false
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${TMP_DIR}/sample.ini"
  )
  normalize_file "${SCRIPT_DIR}/expected.ini" "${TMP_DIR}/expected.docs.norm.ini"
  normalize_file "${TMP_DIR}/sample.ini" "${TMP_DIR}/sample.docs.out.ini"
  diff -u "${TMP_DIR}/expected.docs.norm.ini" "${TMP_DIR}/sample.docs.out.ini" >/dev/null
}

run_lua_dry_run() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export lua__sample_sandbox__SandboxVars__ZombieLore__Transmission=4
    export lua__sample_sandbox__SandboxVars__World__Event=2
    export LUA_CTRL_DRY_RUN=true
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "SandboxVars"
  )
  normalize_file "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.norm.lua"
  normalize_file "${TMP_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.out.lua"
  if ! diff -u "${TMP_DIR}/sample_sandbox.norm.lua" "${TMP_DIR}/sample_sandbox.out.lua" >/dev/null; then
    echo "Lua dry-run modified file" >&2
    exit 1
  fi
}

run_lua_load() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export lua__sample_sandbox__SandboxVars__ZombieLore__Transmission=4
    export lua__sample_sandbox__SandboxVars__World__Event=2
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "SandboxVars"
  )
  if ! grep -q "Transmission = 4" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua apply did not update Transmission" >&2
    exit 1
  fi
  if ! grep -q "Event = 2" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua apply did not update Event" >&2
    exit 1
  fi
}

run_lua_load_docs_style() {
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${TMP_DIR}/sample_sandbox.lua"
  (
    export lua__sample_sandbox__SandboxVars__ZombieLore__Transmission=4
    export lua__sample_sandbox__SandboxVars__World__Event=2
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${TMP_DIR}/sample_sandbox.lua" "SandboxVars"
  )
  if ! grep -q "Transmission = 4" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua docs-style apply did not update Transmission" >&2
    exit 1
  fi
  if ! grep -q "Event = 2" "${TMP_DIR}/sample_sandbox.lua"; then
    echo "Lua docs-style apply did not update Event" >&2
    exit 1
  fi
}

run_env_docs_smoke() {
  local env_dir="${TMP_DIR}/env_sources"
  local out_json="${TMP_DIR}/env.json"
  local index_json="${TMP_DIR}/index.json"
  mkdir -p "${env_dir}/Server"
  cp "${SCRIPT_DIR}/sample.ini" "${env_dir}/Server/pzserver.ini"
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${env_dir}/Server/pzserver_SandboxVars.lua"

  SERVERNAME=pzserver ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${out_json}" IMAGE_TAG="smoke" bash "${ROOT_DIR}/scripts/generate_env_docs.sh"

  if [ ! -s "${out_json}" ]; then
    echo "Env docs did not generate output" >&2
    exit 1
  fi
  if ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"ini__pzserver__Public"' "${out_json}"; then
    echo "Env docs missing ini__pzserver__Public" >&2
    exit 1
  fi
  if ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission"' "${out_json}"; then
    echo "Env docs missing lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission" >&2
    exit 1
  fi
  if [ "$(jq -r '.meta.sources.ini_pzserver' "${out_json}")" != "${env_dir}/Server/pzserver.ini" ]; then
    echo "Env docs missing expected meta source mapping for ini_pzserver" >&2
    exit 1
  fi
  if [ "$(jq -r '.meta.sources.lua_pzserver_SandboxVars' "${out_json}")" != "${env_dir}/Server/pzserver_SandboxVars.lua" ]; then
    echo "Env docs missing expected meta source mapping for lua_pzserver_SandboxVars" >&2
    exit 1
  fi
  if [ ! -s "${index_json}" ]; then
    echo "Env docs index did not generate output" >&2
    exit 1
  fi
  if [ "$(jq -r '.files[] | select(.file=="env.json") | .file' "${index_json}" | head -n1)" != "env.json" ]; then
    echo "Env docs index missing env.json" >&2
    exit 1
  fi
}

run_env_docs_roundtrip_smoke() {
  local env_dir="${TMP_DIR}/env_sources_roundtrip"
  local out_json="${TMP_DIR}/env-roundtrip.json"
  mkdir -p "${env_dir}/Server"
  cp "${SCRIPT_DIR}/sample.ini" "${env_dir}/Server/pzserver.ini"
  cp "${SCRIPT_DIR}/sample_sandbox.lua" "${env_dir}/Server/pzserver_SandboxVars.lua"

  SERVERNAME=pzserver ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${out_json}" IMAGE_TAG="smoke-roundtrip" bash "${ROOT_DIR}/scripts/generate_env_docs.sh"

  local ini_public ini_public_name ini_pvp ini_dropoff
  local lua_transmission lua_event

  ini_public="$(jq -r '.env.generated.ini.pzserver[""][] | select(.name|endswith("__Public")) | .name' "${out_json}")"
  ini_public_name="$(jq -r '.env.generated.ini.pzserver[""][] | select(.name|endswith("__PublicName")) | .name' "${out_json}")"
  ini_pvp="$(jq -r '.env.generated.ini.pzserver.ServerOptions[] | select(.name|endswith("__PVP")) | .name' "${out_json}")"
  ini_dropoff="$(jq -r '.env.generated.ini.pzserver.ServerOptions[] | select(.name|endswith("__DropOffWhiteList")) | .name' "${out_json}")"
  lua_transmission="$(jq -r '.env.generated.lua.pzserver_SandboxVars.ZombieLore[] | select(.name|endswith("__Transmission")) | .name' "${out_json}")"
  lua_event="$(jq -r '.env.generated.lua.pzserver_SandboxVars.World[] | select(.name|endswith("__Event")) | .name' "${out_json}")"

  if [ -z "${ini_public}" ] || [ -z "${ini_public_name}" ] || [ -z "${ini_pvp}" ] || [ -z "${ini_dropoff}" ] || [ -z "${lua_transmission}" ] || [ -z "${lua_event}" ]; then
    echo "Roundtrip smoke failed to extract generated env names" >&2
    exit 1
  fi

  (
    export "${ini_public}=true"
    export "${ini_public_name}=New Name"
    export "${ini_pvp}=false"
    export "${ini_dropoff}=false"
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${env_dir}/Server/pzserver.ini"

    export "${lua_transmission}=4"
    export "${lua_event}=2"
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${env_dir}/Server/pzserver_SandboxVars.lua" "SandboxVars"
  )

  if ! grep -q '^Public=true$' "${env_dir}/Server/pzserver.ini"; then
    echo "Roundtrip INI apply did not update Public" >&2
    exit 1
  fi
  if ! grep -q '^PublicName=New Name$' "${env_dir}/Server/pzserver.ini"; then
    echo "Roundtrip INI apply did not update PublicName" >&2
    exit 1
  fi
  if ! grep -q '^PVP=false$' "${env_dir}/Server/pzserver.ini"; then
    echo "Roundtrip INI apply did not update ServerOptions.PVP" >&2
    exit 1
  fi
  if ! grep -q '^DropOffWhiteList=false$' "${env_dir}/Server/pzserver.ini"; then
    echo "Roundtrip INI apply did not update ServerOptions.DropOffWhiteList" >&2
    exit 1
  fi

  if ! grep -q "Transmission = 4" "${env_dir}/Server/pzserver_SandboxVars.lua"; then
    echo "Roundtrip Lua apply did not update Transmission" >&2
    exit 1
  fi
  if ! grep -q "Event = 2" "${env_dir}/Server/pzserver_SandboxVars.lua"; then
    echo "Roundtrip Lua apply did not update Event" >&2
    exit 1
  fi
}

run_env_name_contract_smoke() {
  local env_dir="${TMP_DIR}/env_sources_contract"
  local out_json="${TMP_DIR}/env-contract.json"
  mkdir -p "${env_dir}/Server"

  cat > "${env_dir}/Server/pzserver_network.ini" <<'EOF'
Voice__Quality=1

[Voice]
Quality=4
EOF

  cat > "${env_dir}/Server/pzserver_SandboxVars.lua" <<'EOF'
SandboxVars = {
  ZombieLore = {
    Transmission = 2,
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_LootRules.lua" <<'EOF'
return {
  Enabled = true,
  Zones = {
    Town = {
      Weapons = 2,
    },
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_MultiTables.lua" <<'EOF'
SandboxVars = {
  ZombieLore = {
    Transmission = 2,
  },
}
SandboxVars2 = {
  ZombieLore = {
    Transmission = 4,
  },
}
EOF

  SERVERNAME=pzserver ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${out_json}" IMAGE_TAG="smoke-contract" bash "${ROOT_DIR}/scripts/generate_env_docs.sh"

  if [ "$(jq -r '.env.generated.ini.pzserver_network[""][] | select(.name=="ini__pzserver_network__Voice__Quality") | .name' "${out_json}")" != "ini__pzserver_network__Voice__Quality" ]; then
    echo "Contract smoke missing root INI underscore key name" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_network.Voice[] | select(.name=="ini__pzserver_network__Voice__Quality") | .name' "${out_json}")" != "ini__pzserver_network__Voice__Quality" ]; then
    echo "Contract smoke missing section INI key name" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_SandboxVars.ZombieLore[] | select(.name=="lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission") | .name' "${out_json}")" != "lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission" ]; then
    echo "Contract smoke missing single-table Lua key name" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_LootRules[""].Zones[] | select(.name=="lua__pzserver_LootRules__Zones__Town__Weapons") | .name' "${out_json}")" != "lua__pzserver_LootRules__Zones__Town__Weapons" ]; then
    echo "Contract smoke missing return-table Lua key name" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MultiTables.SandboxVars.ZombieLore[] | select(.name=="lua__pzserver_MultiTables__SandboxVars__ZombieLore__Transmission") | .name' "${out_json}")" != "lua__pzserver_MultiTables__SandboxVars__ZombieLore__Transmission" ]; then
    echo "Contract smoke missing multi-table first key name" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MultiTables.SandboxVars2.ZombieLore[] | select(.name=="lua__pzserver_MultiTables__SandboxVars2__ZombieLore__Transmission") | .name' "${out_json}")" != "lua__pzserver_MultiTables__SandboxVars2__ZombieLore__Transmission" ]; then
    echo "Contract smoke missing multi-table second key name" >&2
    exit 1
  fi

  (
    export ini__pzserver_network__Voice__Quality=9
    bash "${ROOT_DIR}/scripts/apply_ini_vars.sh" "${env_dir}/Server/pzserver_network.ini"

    export lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission=7
    bash "${ROOT_DIR}/scripts/apply_lua_vars.sh" "${env_dir}/Server/pzserver_SandboxVars.lua" "SandboxVars"
  )

  if ! grep -q '^Quality=9$' "${env_dir}/Server/pzserver_network.ini"; then
    echo "Contract smoke runtime apply failed for INI docs-style name" >&2
    exit 1
  fi
  if ! grep -q 'Transmission = 7' "${env_dir}/Server/pzserver_SandboxVars.lua"; then
    echo "Contract smoke runtime apply failed for Lua docs-style name" >&2
    exit 1
  fi
}

run_env_docs_rich_smoke() {
  local env_dir="${TMP_DIR}/env_sources_rich"
  local out_json="${TMP_DIR}/env-rich.json"
  local index_json="${TMP_DIR}/index.json"
  local gen_log="${TMP_DIR}/env-rich.log"
  mkdir -p "${env_dir}/Server"

  cat > "${env_dir}/Server/pzserver.ini" <<'EOF'
# Global options
Public=true
PublicName=Rich Server

[ServerOptions]
# PvP flag
PVP=false
MaxPlayers=24 ; max players inline

[Steam]
SteamVAC=true
EOF

  cat > "${env_dir}/Server/pzserver_spawnregions.ini" <<'EOF'
[WestPoint]
# points to lua region file
file=media/maps/West Point, KY/spawnpoints.lua

[Muldraugh]
file=media/maps/Muldraugh, KY/spawnpoints.lua
EOF

  cat > "${env_dir}/Server/pzserver_network.ini" <<'EOF'
# network tuning
UDPBuffer=65536
Voice__Quality=1

[Voice]
# voice enabled
Enabled=true
Quality=4 ; voice quality inline

[Connection]
MaxConnections=128
EOF

  cat > "${env_dir}/Server/pzserver_case.ini" <<'EOF'
[Case]
PVP=true
pvp=false
EOF

  cat > "${env_dir}/Server/pzserver_parser.ini" <<'EOF'
[Quotes]
Welcome="hello;world # not comment" ; quoted comment kept
DupKey=1
DupKey=2
EOF

  cat > "${env_dir}/Server/pzserver_SandboxVars.lua" <<'EOF'
SandboxVars = {
  ZombieLore = {
    -- spread mode
    Transmission = 2,
    Mortality = 5,
  },
  World = {
    Event = 3,
    Temperature = 4,
  },
  Farming = {
    Abundance = 2,
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_MapSettings.lua" <<'EOF'
MapSettings = {
  Zones = {
    Forest = {
      Loot = 2,
      Threat = 1,
    },
    City = {
      Loot = 4,
      Threat = 4,
    }
  },
  Weather = {
    Rain = 3,
  }
}
EOF

  cat > "${env_dir}/Server/pzserver_AdvancedSettings.lua" <<'EOF'
AdvancedSettings = {
  -- enable advanced mode
  Enabled = true,
  Loot = {
    Containers = {
      House = {
        -- deep rarity value
        RareChance = 6,
      },
      Warehouse = {
        RareChance = 9,
      },
    },
  },
  Zombies = {
    Speeds = {
      Day = 2,
      Night = 4,
    },
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_LootRules.lua" <<'EOF'
return {
  -- root enabled flag
  Enabled = true,
  Multipliers = {
    Food = 2,
    Weapons = 1,
  },
  Zones = {
    Town = {
      -- town weapon multiplier
      Weapons = 2,
    },
    Rural = {
      Weapons = 1,
    },
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_MultiTables.lua" <<'EOF'
SandboxVars = {
  ZombieLore = {
    Transmission = 2,
  },
}
SandboxVars2 = {
  ZombieLore = {
    Transmission = 4,
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_BracketKeys.lua" <<'EOF'
return {
  Zones = {
    ["Town-Center"] = 2, -- bracket key description
    ["A\"B"] = 3, -- escaped quote bracket key
    ['A\'B'] = 5, -- escaped single quote bracket key
    ['Semi;Colon'] = "A--B", -- single quote bracket key
    [42] = 7, -- numeric bracket key
  },
  Banner = "--literal value", -- banner description
  Literal = "--no inline comment",
  Dup = 1,
  Dup = 2,
}
EOF

  cat > "${env_dir}/Server/pzserver_MixedBracketNested.lua" <<'EOF'
return {
  Mix = {
    ["x"] = {
      [1] = {
        ['y'] = 11, -- mixed nested value
      },
    },
  },
  ArrayLike = {
    10,
    20,
    30,
  },
}
EOF

  cat > "${env_dir}/Server/pzserver_MalformedBracket.lua" <<'EOF'
return {
  Bad = {
    ["MissingEnd = 1, -- malformed bracket key
    ['AlsoBad] = 2, -- malformed bracket key
    [abc] = 3, -- unsupported bare identifier bracket key
    Good = 4, -- valid neighbor key
  },
}
EOF

  SERVERNAME=pzserver ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${out_json}" IMAGE_TAG="smoke-rich" bash "${ROOT_DIR}/scripts/generate_env_docs.sh" 2>"${gen_log}"

  if [ ! -s "${out_json}" ]; then
    echo "Rich env docs did not generate output" >&2
    exit 1
  fi

  if [ "$(jq -r '.env.custom | has("args") and has("env_hooks") and has("vars")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing expected env.custom groups" >&2
    exit 1
  fi
  if [ "$(jq -r '.meta.sources | has("hooks_args") and has("hooks_env_hooks") and has("hooks_vars")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing expected handcrafted source IDs" >&2
    exit 1
  fi
  if [ "$(jq -r '.meta.sources.lua_pzserver_MultiTables' "${out_json}")" != "${env_dir}/Server/pzserver_MultiTables.lua" ]; then
    echo "Rich env docs missing expected meta source mapping for lua_pzserver_MultiTables" >&2
    exit 1
  fi

  if [ "$(jq -r '.env.generated.ini.pzserver | has("") and has("ServerOptions")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested INI sections for pzserver.ini" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_spawnregions | has("WestPoint") and has("Muldraugh")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested INI sections for spawnregions" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_network | has("") and has("Voice") and has("Connection")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested INI sections for network" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_case | has("Case")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested INI sections for case file" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_parser | has("Quotes")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested INI sections for parser file" >&2
    exit 1
  fi

  if [ "$(jq -r '.env.generated.lua.pzserver_SandboxVars | has("ZombieLore") and has("World") and has("Farming")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing trimmed Lua groups for SandboxVars" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MapSettings | has("Zones") and has("Weather")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing trimmed Lua groups for MapSettings" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_AdvancedSettings | has("Enabled") and has("Loot") and has("Zombies")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing trimmed Lua groups for AdvancedSettings" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_LootRules[""] | has("Enabled") and has("Multipliers") and has("Zones")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing nested Lua groups for LootRules" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MultiTables | has("SandboxVars") and has("SandboxVars2")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing retained top-level Lua groups for MultiTables" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""] | has("Zones") and has("Banner") and has("Literal") and has("Dup")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing Lua groups for bracket-keys file" >&2
    exit 1
  fi

  if [ "$(jq -r '.env.generated.ini.pzserver.ServerOptions[] | select(.name=="ini__pzserver__ServerOptions__MaxPlayers") | .description' "${out_json}")" != "max players inline" ]; then
    echo "Rich env docs missing inline INI description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_SandboxVars.ZombieLore[] | select(.name=="lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission") | .description' "${out_json}")" != "spread mode" ]; then
    echo "Rich env docs missing Lua comment description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_network.Voice[] | select(.name=="ini__pzserver_network__Voice__Quality") | .description' "${out_json}")" != "voice quality inline" ]; then
    echo "Rich env docs missing inline INI description extraction for network" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_network[""][] | select(.name=="ini__pzserver_network__Voice__Quality") | .name' "${out_json}")" != "ini__pzserver_network__Voice__Quality" ]; then
    echo "Rich env docs missing collision-safe INI promoted name for root Voice__Quality" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_parser.Quotes[] | select(.name=="ini__pzserver_parser__Quotes__Welcome") | .description' "${out_json}")" != "quoted comment kept" ]; then
    echo "Rich env docs failed quote-aware INI inline comment parsing" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_case.Case[] | select(.name=="ini__pzserver_case__Case__PVP") | .name' "${out_json}")" != "ini__pzserver_case__Case__PVP" ]; then
    echo "Rich env docs missing case-sensitive INI key PVP" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.ini.pzserver_case.Case[] | select(.name=="ini__pzserver_case__Case__pvp") | .name' "${out_json}")" != "ini__pzserver_case__Case__pvp" ]; then
    echo "Rich env docs missing case-sensitive INI key pvp" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_AdvancedSettings.Enabled[] | select(.name=="lua__pzserver_AdvancedSettings__AdvancedSettings__Enabled") | .description' "${out_json}")" != "enable advanced mode" ]; then
    echo "Rich env docs missing top-level Lua description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_AdvancedSettings.Loot[] | select(.name=="lua__pzserver_AdvancedSettings__AdvancedSettings__Loot__Containers__House__RareChance") | .description' "${out_json}")" != "deep rarity value" ]; then
    echo "Rich env docs missing deep nested Lua description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_LootRules[""].Enabled[] | select(.name=="lua__pzserver_LootRules__Enabled") | .description' "${out_json}")" != "root enabled flag" ]; then
    echo "Rich env docs missing return-table top-level Lua description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_LootRules[""].Zones[] | select(.name=="lua__pzserver_LootRules__Zones__Town__Weapons") | .description' "${out_json}")" != "town weapon multiplier" ]; then
    echo "Rich env docs missing return-table nested Lua description extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MultiTables.SandboxVars.ZombieLore[] | select(.name=="lua__pzserver_MultiTables__SandboxVars__ZombieLore__Transmission") | .name' "${out_json}")" != "lua__pzserver_MultiTables__SandboxVars__ZombieLore__Transmission" ]; then
    echo "Rich env docs missing first top-level Lua group extraction in MultiTables" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MultiTables.SandboxVars2.ZombieLore[] | select(.name=="lua__pzserver_MultiTables__SandboxVars2__ZombieLore__Transmission") | .name' "${out_json}")" != "lua__pzserver_MultiTables__SandboxVars2__ZombieLore__Transmission" ]; then
    echo "Rich env docs missing second top-level Lua group extraction in MultiTables" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Zones[] | select(.name=="lua__pzserver_BracketKeys__Zones__Town-Center") | .description' "${out_json}")" != "bracket key description" ]; then
    echo "Rich env docs missing double-quoted Lua bracket key extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Zones[] | select(.name=="lua__pzserver_BracketKeys__Zones__Semi;Colon") | .description' "${out_json}")" != "single quote bracket key" ]; then
    echo "Rich env docs missing single-quoted Lua bracket key extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Zones[] | select(.name=="lua__pzserver_BracketKeys__Zones__42") | .description' "${out_json}")" != "numeric bracket key" ]; then
    echo "Rich env docs missing numeric Lua bracket key extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Zones[] | select(.description=="escaped quote bracket key") | .name' "${out_json}")" != "lua__pzserver_BracketKeys__Zones__A\"B" ]; then
    echo "Rich env docs missing escaped-quote Lua bracket key extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Zones[] | select(.description=="escaped single quote bracket key") | .name' "${out_json}")" != "lua__pzserver_BracketKeys__Zones__A'B" ]; then
    echo "Rich env docs missing escaped-single-quote Lua bracket key extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MixedBracketNested[""].Mix[] | select(.name=="lua__pzserver_MixedBracketNested__Mix__x__1__y") | .description' "${out_json}")" != "mixed nested value" ]; then
    echo "Rich env docs missing mixed bracket nested Lua extraction" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MixedBracketNested[""].ArrayLike // {} | has("1") or has("2") or has("3")' "${out_json}")" != "false" ]; then
    echo "Rich env docs unexpectedly generated Lua array index entries" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MalformedBracket[""] | has("Bad")' "${out_json}")" != "true" ]; then
    echo "Rich env docs missing malformed-bracket Lua group" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_MalformedBracket[""].Bad[] | select(.name=="lua__pzserver_MalformedBracket__Bad__Good") | .description' "${out_json}")" != "valid neighbor key" ]; then
    echo "Rich env docs failed to extract valid key adjacent to malformed bracket keys" >&2
    exit 1
  fi
  if [ "$(jq -r '[.env.generated.lua.pzserver_MalformedBracket[""].Bad[]?.name | select(test("MissingEnd|AlsoBad|abc"))] | length' "${out_json}")" != "0" ]; then
    echo "Rich env docs unexpectedly extracted malformed Lua bracket keys" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Banner[] | select(.name=="lua__pzserver_BracketKeys__Banner") | .description' "${out_json}")" != "banner description" ]; then
    echo "Rich env docs failed quote-aware Lua inline comment parsing" >&2
    exit 1
  fi
  if [ "$(jq -r '.env.generated.lua.pzserver_BracketKeys[""].Literal[] | select(.name=="lua__pzserver_BracketKeys__Literal") | .description' "${out_json}")" != "" ]; then
    echo "Rich env docs falsely parsed Lua inline comment inside quoted value" >&2
    exit 1
  fi
  if ! grep -q 'Warning: duplicate INI generated env name ini__pzserver_parser__Quotes__DupKey (occurrences=2)' "${gen_log}"; then
    echo "Rich env docs missing duplicate INI warning" >&2
    exit 1
  fi
  if ! grep -q 'Warning: duplicate LUA generated env name lua__pzserver_BracketKeys__Dup (occurrences=2)' "${gen_log}"; then
    echo "Rich env docs missing duplicate Lua warning" >&2
    exit 1
  fi
  if SERVERNAME=pzserver ENV_SOURCES_DIR="${env_dir}" OUTPUT_PATH="${TMP_DIR}/env-rich-strict.json" IMAGE_TAG="smoke-rich-strict" ENV_DOCS_FAIL_ON_DUPLICATES=true bash "${ROOT_DIR}/scripts/generate_env_docs.sh" >/dev/null 2>"${TMP_DIR}/env-rich-strict.log"; then
    echo "Rich env docs strict duplicate mode did not fail on duplicates" >&2
    exit 1
  fi
  if ! grep -q 'Error: duplicate generated env names found' "${TMP_DIR}/env-rich-strict.log"; then
    echo "Rich env docs strict duplicate mode missing failure message" >&2
    exit 1
  fi
  if [ ! -s "${index_json}" ]; then
    echo "Rich env docs index did not generate output" >&2
    exit 1
  fi
  if [ "$(jq -r '.files[] | select(.file=="env-rich.json") | .file' "${index_json}" | head -n1)" != "env-rich.json" ]; then
    echo "Rich env docs index missing env-rich.json" >&2
    exit 1
  fi
}

echo "Running INI helper smoke tests..."
run_ini_dry_run
echo "INI dry-run ok"
run_ini_load
echo "INI apply ok"
run_ini_load_docs_style
echo "INI docs-style apply ok"

echo "Running Lua helper smoke tests..."
run_lua_dry_run
echo "Lua dry-run ok"
run_lua_load
echo "Lua apply ok"
run_lua_load_docs_style
echo "Lua docs-style apply ok"

echo "Running env docs smoke test..."
run_env_docs_smoke
echo "Env docs ok"

echo "Running env docs roundtrip smoke test..."
run_env_docs_roundtrip_smoke
echo "Env docs roundtrip ok"

echo "Running env name contract smoke test..."
run_env_name_contract_smoke
echo "Env name contract ok"

echo "Running rich env docs smoke test..."
run_env_docs_rich_smoke
echo "Rich env docs ok"

echo "Smoke tests passed."
