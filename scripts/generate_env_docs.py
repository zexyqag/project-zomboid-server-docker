#!/usr/bin/env python3

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Set, Tuple


INI_SAMPLE_FILES = [
    "smoke/sample.ini",
    "smoke/expected.ini",
]

LUA_SAMPLE_FILES = [
    "smoke/sample_sandbox.lua",
    "smoke/expected_sandbox.lua",
]


def parse_env_template(path: Path) -> Set[str]:
    envs: Set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*([A-Z][A-Z0-9_]*)=", line)
        if match:
            envs.add(match.group(1))
    return envs


def parse_entry_envs(path: Path) -> Set[str]:
    text = path.read_text(encoding="utf-8")
    referenced: Set[str] = set()
    assigned: Set[str] = set()

    for match in re.finditer(r"\$\{([A-Z][A-Z0-9_]*)\}|\$([A-Z][A-Z0-9_]*)", text):
        referenced.add(match.group(1) or match.group(2))

    for match in re.finditer(r"^\s*([A-Z][A-Z0-9_]*)=", text, flags=re.MULTILINE):
        assigned.add(match.group(1))

    for match in re.finditer(r"\bfor\s+([A-Z][A-Z0-9_]*)\s+in\b", text):
        assigned.add(match.group(1))

    for match in re.finditer(r"\blocal\s+([A-Z][A-Z0-9_]*)\b", text):
        assigned.add(match.group(1))

    filtered = referenced - assigned
    return filtered


def parse_ini_keys(paths: Iterable[Path]) -> List[Dict[str, Any]]:
    results: Dict[str, Dict[str, Any]] = {}
    for path in paths:
        if not path.exists():
            continue
        section = ""
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith(";") or line.startswith("#"):
                continue
            section_match = re.match(r"\[([^\]]+)\]", line)
            if section_match:
                section = section_match.group(1).strip()
                continue
            kv_match = re.match(r"([^=]+)=(.*)", line)
            if kv_match:
                key = kv_match.group(1).strip()
                env_name = f"INIVARS_{key}" if section == "" else f"INIVARS_{section}__{key}"
                if env_name not in results:
                    results[env_name] = {
                        "env_name": env_name,
                        "section": section,
                        "key": key,
                        "sources": [],
                    }
                results[env_name]["sources"].append(str(path.as_posix()))
    return list(results.values())


def _encode_lua_part(value: str) -> str:
    return value.replace("_", "__")


def parse_lua_keys(paths: Iterable[Path]) -> List[Dict[str, Any]]:
    results: Dict[str, Dict[str, Any]] = {}
    for path in paths:
        if not path.exists():
            continue
        in_sandbox = False
        depth = 0
        stack: List[str] = []
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("--"):
                continue

            if not in_sandbox:
                if re.match(r"SandboxVars\s*=\s*\{\s*$", line):
                    in_sandbox = True
                    depth = 1
                    stack = []
                continue

            if re.match(r"}\s*,?\s*$", line):
                depth -= 1
                if depth == 0:
                    in_sandbox = False
                    stack = []
                elif stack:
                    stack.pop()
                continue

            table_match = re.match(r"([A-Za-z0-9_]+)\s*=\s*\{\s*$", line)
            if table_match:
                stack.append(table_match.group(1))
                depth += 1
                continue

            assign_match = re.match(r"([A-Za-z0-9_]+)\s*=\s*(.+?)(,?)\s*$", line)
            if assign_match:
                key = assign_match.group(1)
                path_parts = stack + [key]
                path_value = ".".join(path_parts)
                encoded_parts = [_encode_lua_part(part) for part in path_parts]
                env_name = "SANDBOXVARS_" + "_".join(encoded_parts)
                if env_name not in results:
                    results[env_name] = {
                        "env_name": env_name,
                        "path": path_value,
                        "sources": [],
                    }
                results[env_name]["sources"].append(str(path.as_posix()))
    return list(results.values())


def collect_source_files(repo_root: Path, extracted_root: Path) -> Tuple[List[Path], List[Path], str]:
    ini_files: List[Path] = []
    lua_files: List[Path] = []
    source_mode = "repo_samples"

    if extracted_root.exists():
        ini_files = sorted(extracted_root.rglob("*.ini"))
        lua_files = sorted(extracted_root.rglob("*.lua"))
        if ini_files or lua_files:
            source_mode = "image_extract"
            return ini_files, lua_files, source_mode

    ini_files = [repo_root / path for path in INI_SAMPLE_FILES]
    lua_files = [repo_root / path for path in LUA_SAMPLE_FILES]
    return ini_files, lua_files, source_mode


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    output_path = Path(os.environ.get("OUTPUT_PATH", repo_root / "docs" / "env.json"))
    sources_root = Path(os.environ.get("ENV_SOURCES_DIR", repo_root / "docs" / "env_sources"))
    image_tag = os.environ.get("IMAGE_TAG")

    entry_sh = repo_root / "scripts" / "entry.sh"
    env_template = repo_root / ".env.template"

    handcrafted_envs = parse_entry_envs(entry_sh)
    documented_envs: Set[str] = parse_env_template(env_template) if env_template.exists() else set()

    handcrafted: List[Dict[str, Any]] = []
    for name in sorted(handcrafted_envs):
        handcrafted.append(
            {
                "name": name,
                "source": "scripts/entry.sh",
                "documented": name in documented_envs,
            }
        )

    ini_files, lua_files, source_mode = collect_source_files(repo_root, sources_root)
    ini_envs = parse_ini_keys(ini_files)
    lua_envs = parse_lua_keys(lua_files)

    payload: Dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "sources": {
            "entry": "scripts/entry.sh",
            "env_template": ".env.template",
            "source_mode": source_mode,
            "ini_files": [str(path.as_posix()) for path in ini_files],
            "lua_files": [str(path.as_posix()) for path in lua_files],
        },
        "image_tag": image_tag,
        "handcrafted_env": handcrafted,
        "ini_env": sorted(ini_envs, key=lambda item: str(item["env_name"])),
        "lua_env": sorted(lua_envs, key=lambda item: str(item["env_name"])),
        "patterns": [
            {
                "prefix": "INIVARS_",
                "description": "Override server INI keys. Use INIVARS_Key=Value or INIVARS_Section__Key=Value.",
            },
            {
                "prefix": "SANDBOXVARS_",
                "description": "Override SandboxVars Lua keys. Use '_' as path separator and '__' for a literal underscore.",
            },
        ],
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
