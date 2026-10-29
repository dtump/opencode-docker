# Proposal

## Why

The image pins OpenCode 1.x (`opencode-ai@1.18.16`), but OpenCode 2 is the current major line (2.0.0 released 2026-09-11; 2.2.0 on 2026-10-27). The 1.x npm package is frozen — new releases only land on 2.x — so staying on 1.x means drifting off the supported line: no current terminal client, no ordered permission/policy model, no background-service architecture.

## What Changes

- **BREAKING (distribution):** OpenCode 2 is published as `@opencode/cli`, not `opencode-ai`. The Dockerfile install and the `update_pins.py` tool registry switch to `@opencode/cli`. The `--ignore-scripts` + explicit `postinstall.mjs` install pattern is unchanged (same package shape, re-reviewed per the Dockerfile's standing note).
- Pin `OPENCODE_VERSION=2.2.0` via `uv run update_pins.py --pin opencode=2.2.0` (soak override — see design.md D2 for the CI consequence).
- `opencode --version` output changes from `1.18.16` to `opencode v2.2.0`; the CI pin-match assertion is updated to match.
- Drop `OPENCODE_EXPERIMENTAL_AGENT_TEAMS=1` (no such variable in OpenCode 1.x ≥ 1.19 or 2.x; it was inherited from Claude Code's `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). Keep `OPENCODE_DISABLE_AUTOUPDATE=1` (OpenCode 2 still honours it) and `IS_SANDBOX=1` (legacy `HOST_UID=0` safety net).
- Harden `entrypoint.sh`: the `/root` ownership walk also filters `No such file or directory` chown errors, because OpenCode 2's background service keeps transient files (flock lock dirs, the `service.json` registration, SQLite sidecars) under `/root` on the shared volume, and a concurrent container's start can race their removal.
- Rewrite the `host-config-parity` and `persistent-session-storage` specs, which still describe Claude Code after the fork migration, to match OpenCode 2 reality.
- Archive the six implemented-but-unfinished pre-rename changes without syncing their stale delta specs (claude-flavoured, partly superseded by the gh-auth-proxy sidecar); spec modernisation is a separate follow-up.

**User-facing behavior changes (BREAKING):** v1 conversation history does not migrate — OpenCode 2 starts a fresh session database and imports only provider credentials. Config locations, the `opencode.docker.json` seed, host config mounts, and wrapper flags are unchanged; a v1-schema `opencode.json` is accepted and normalised in memory.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `host-config-parity`: mount paths and seed file move from Claude Code locations (`~/.claude`, `settings.docker.json`) to OpenCode locations (`~/.config/opencode`, `opencode.docker.json`); OpenCode 2 config-schema compatibility is specified; the inert `prompts/` and `statusline-command.sh` mounts are documented as such.
- `persistent-session-storage`: persistence semantics move from Claude Code's `/root/.claude/projects/` to OpenCode 2's named volumes + SQLite database; adds background-service registration lifecycle, v1→v2 history non-migration, credential import, and concurrent-container ownership-fixup tolerance.

## Impact

- Files: `Dockerfile`, `update_pins.py`, `pins/opencode.env` (plus routine soak-gated bumps to `pins/{openspec,pnpm,uv,glab,awscli}.env` from the same refresh), `.github/workflows/ci.yml`, `README.md`, `entrypoint.sh`, `openspec/` (this change + two rewritten specs + six archived changes).
- No `run.sh` changes: `--auto`, `--continue`/`-c`, `--session`/`-s`, `--fork`, and the directory argument all still exist in OpenCode 2 with the same meaning.
- CI: the `npm-pinned tools supply-chain audit` job fails until 2026-11-03 because the pinned 2.2.0 is inside the 7-day soak window (the `--pin` override bypasses soak at write time; `--audit` re-checks the pinned version). See design.md D2 for options.
