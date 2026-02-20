# Development Guide

This document is for contributors and maintainers.
The main README is intentionally user/operator oriented.

## Repository goals

- Build and publish a reliable Project Zomboid dedicated server image.
- Provide safe runtime configuration through environment variables.
- Auto-generate machine-readable environment docs from real server config sources.

## High-level architecture

- Container startup entrypoint: `scripts/entry.sh`
- Shared runtime helpers: `scripts/lib/runtime_helpers.sh`
- Env hook system (ordered by `DEPENDS_ON`): `scripts/env_hooks/**`
- INI mutation engine: `scripts/apply_ini_vars.sh`
- Lua mutation engine: `scripts/apply_lua_vars.sh`
- Workshop collection resolver: `scripts/resolve_workshop_collection.sh`
- Map scan/copy helper: `scripts/search_folder.sh`

## Startup flow

At runtime, `entry.sh`:

1. Resolves the server INI path.
2. Discovers env hooks in `scripts/env_hooks` (excluding `vars/`).
3. Applies hooks in dependency order using `DEPENDS_ON`.
4. Falls back to name-ordered execution for unresolved dependency cycles.
5. Sets runtime fixes (`LD_LIBRARY_PATH`, permissions).
6. Launches `start-server.sh` as the `steam` user.

## Env hooks conventions

Each hook can define:

- `DESCRIPTION`: short purpose text (also used by env-doc tooling)
- `REPLACES`: hook names/env aliases replaced by this hook (replaced hooks are skipped at runtime)
- `DEPENDS_ON`: space-separated hook dependencies
- `manual_apply()`: implementation entrypoint

`REPLACES` is used in two places:

- Runtime: if a `REPLACES` token matches another hook name, that hook is skipped.
- Env docs/runtime env filtering: tokens should reference generated docs-style env entries (for example `ini__pzserver__Password`) to mark/ignore replaced auto-generated entries.

Related directories:

- `scripts/env_hooks/`: runtime behavior hooks
- `scripts/env_hooks/args/`: command-line argument builders
- `scripts/env_hooks/vars/`: declarative/env-doc variables (not executed as hooks)

## Configuration model

The runtime uses docs-style generated env names.

- INI docs prefix: `ini__`
- Lua docs prefix: `lua__`
- Name codec helpers: `scripts/lib/env_name_codec.sh`

Security rule:

- Do not reintroduce direct `INI_Password` / `INI_RCONPassword` usage for secrets.
- Keep using dedicated secret envs and `*_FILE` variants (`PASSWORD`, `RCONPASSWORD`, `ADMINPASSWORD`, etc.).

## Env docs pipeline

Core scripts:

- `scripts/extract_env_sources.sh`
- `scripts/generate_env_docs.sh`
- `scripts/generate_env_index.sh`

Generated entries include `replaced_by` per env item when a custom hook replaces that generated entry.

Current env docs JSON shape (`scripts/generate_env_docs.sh`):

- Entries are objects keyed by logical setting name (not single-item arrays).
- Each entry includes:
	- `name`: logical key within its group/section
	- `env_name`: full environment variable name to export
	- `description`
	- `source_ids`
	- `replaced_by`
- `env.custom.args`, `env.custom.hooks`, and `env.custom.vars` follow the same entry shape.
- `env.generated.ini` is grouped as `<file_key> -> <section> -> <name> -> entry`.
- `env.generated.lua` is grouped as `<file_key> -> ... -> <name> -> entry`, with logical names using subgroup-relative path segments joined by `__` when needed for uniqueness.

Preview data checked into repo:

- `data/env_preview/env.json`
- `data/env_preview/index.json`
- `data/env_preview/env_sources/`

CI workflow also generates per-tag docs and publishes them to the `docs/env` branch.

## Testing

Smoke tests are in `smoke/run_smoke.sh`.

They cover:

- INI apply and dry-run behavior
- Lua apply and dry-run behavior
- Env docs generation and roundtrip contracts
- Parser edge cases and naming contracts

Run locally:

```bash
bash smoke/run_smoke.sh
```

## CI/CD overview

- Image build/publish workflow: `.github/workflows/docker-image.yml`
- Env docs workflow: `.github/workflows/env-docs.yml`

`docker-image.yml` builds stable/unstable tags and versioned tags based on detected latest upstream PZ versions.

## Contributor checklist

- Keep operator UX simple in `README.MD`.
- Add/adjust hooks with `DESCRIPTION` and correct dependencies.
- Keep schema and naming contracts consistent with smoke tests.
- Update smoke tests when changing parsing or naming contracts.
- Validate with `bash smoke/run_smoke.sh` before opening PRs.
