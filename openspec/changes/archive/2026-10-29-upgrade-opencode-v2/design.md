# Design

## Context

The image pinned `opencode-ai@1.18.16` (OpenCode 1.x). OpenCode 2 (2.0.0 released 2026-09-11; 2.2.0 on 2026-10-27) is a new major line: a rewritten terminal client, an ordered permissions/policies model, a shared per-user background service, and a new distribution package (`@opencode/cli` on npm; `opencode-ai` is frozen at 1.x). The wrapper (`run.sh`), entrypoint, credential opt-ins, and config mounts are version-agnostic; the upgrade touches the install mechanism, the version-output contract, and persistent-state semantics. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**

- Ship OpenCode 2.2.0 through the same pinned, supply-chain-gated install path (`--ignore-scripts` + explicit postinstall; npm dist.integrity + CI `npm audit signatures`).
- Keep every wrapper flag and host-config mount working unchanged.
- Record the v1→v2 behavior deltas in the specs.

**Non-Goals:**

- Migrating v1 conversation history (upstream provides no session import; only credentials import).
- Converting user configs to v2-native schema (the v1 schema is accepted and normalised in memory).
- Removing the inert `prompts/` and `statusline-command.sh` mounts (separate cleanup).
- Syncing the six pre-rename changes' stale delta specs (claude-flavoured, partly superseded by the gh-auth-proxy sidecar; spec modernisation is a separate follow-up).
- Tracking upstream schubergphilis/claude-docker divergence (separate follow-up).

## Decisions

- **D1: Install from `@opencode/cli` via npm, keeping the postinstall flow.** The v2 package has the same shape as `opencode-ai` (per-arch optional-dep native binary + `postinstall.mjs` launcher), so the existing trust model is unchanged: version pin in `pins/opencode.env`, `npm install -g --ignore-scripts`, explicit `node "$(npm root -g)/@opencode/cli/postinstall.mjs"`, registry dist.integrity verification, and CI `npm audit signatures` (passes for 2.2.0, with attestations). Alternative considered: standalone binary from opencode.ai / GitHub releases — rejected because it would lose npm's registry-integrity check and the existing CI signature audit. The v2 postinstall was re-reviewed per the Dockerfile's standing note: it selects the platform binary (with baseline/musl/AVX2 fallbacks), version-checks the platform package against `optionalDependencies`, verifies the copy with `--version`, and falls back to a separate `npm install --ignore-scripts` — the same security properties as v1.
- **D2: Pin 2.2.0 with a soak override.** 2.2.0 (2026-10-27) is inside the 7-day soak window; a plain `update_pins.py` refresh would select 2.1.2. The operator accepted the override. Consequence: CI's `update_pins.py --audit` fails until 2026-11-03 — the override bypasses soak at write time, but the audit re-checks the pinned version. Options if a green pipeline is required: wait for the soak to elapse, or pin 2.1.2 and let a routine refresh move to 2.2.x later.
- **D3: Keep `OPENCODE_DISABLE_AUTOUPDATE=1`, drop `OPENCODE_EXPERIMENTAL_AGENT_TEAMS=1`, keep `IS_SANDBOX=1`.** Verified in the v2 source (`packages/cli/src/services/updater.ts`) that `OPENCODE_DISABLE_AUTOUPDATE` still suppresses update checks, keeping the image pin authoritative. `OPENCODE_EXPERIMENTAL_AGENT_TEAMS` has no consumer in OpenCode 1.x ≥ 1.19 or 2.x (it was inherited from `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`). `IS_SANDBOX` has no consumer in OpenCode either, but it is documented as a legacy safety net for the `HOST_UID=0` path and is harmless — kept to avoid an unrelated behavior change in this PR.
- **D4: Update the CI version assertion to the v2 output format.** `opencode --version` prints `opencode v2.2.0` (verified against a locally installed `@opencode/cli@2.2.0`); the CI smoke step now expects `opencode v${EXPECTED}`.
- **D5: Leave the background service enabled (no `--standalone`).** The service self-heals: a stale `service.json` from a killed container is detected via the loopback health check and replaced on the next command (verified live against 2.2.0). `--standalone` would avoid the shared registration entirely but changes session/service semantics for no user-visible gain. The registration's plaintext localhost password persists in the `opencode-root` volume — the same sensitivity class as the OAuth tokens already stored there.
- **D6: Tolerate ENOENT in the entrypoint chown walk.** OpenCode 2 keeps transient files under `/root` on the shared volume (flock lock dirs under `~/.local/state/opencode/locks/`, the `service.json` registration, SQLite `-wal`/`-shm` sidecars). A second container starting while another session's service runs can race their removal; a vanished file needs no chown. Filtered alongside the existing EROFS filter; genuine errors still warn. Verified with a simulated vanishing-file race.
- **D7: Rewrite two specs; archive six stale changes without syncing them.** `host-config-parity` and `persistent-session-storage` still described Claude Code after the fork migration; this change rewrites them to OpenCode 2 reality. The six pre-rename changes are implemented but their deltas are claude-flavoured and partly superseded (e.g. add-tfe-support's `--gh` token-forwarding scenarios contradict the shipped auth-proxy sidecar), so they are archived as historical records. Spec modernisation for the remaining stale specs (cli-help, package-managers, external-cli-tools, multi-workspace-mounts) is a separate follow-up.

## Risks / Trade-offs

- **[Risk] 2.2.0 is 2 days old at pin time (soak override).** → Mitigation: the CI audit job is red until 2026-11-03; re-pin to a soaked version then, or pin 2.1.2 for a green pipeline. npm registry signatures + attestations verified for 2.2.0.
- **[Risk] v1 conversation history is lost on upgrade.** → Mitigation: specified in `persistent-session-storage`; credentials carry over (`auth.json` import), so users keep provider access without re-login. Users who still need v1 history keep the old image until done with it.
- **[Risk] Concurrent containers on the same volumes now race on v2 service state (shared SQLite DB, registration ping-pong).** → Mitigation: SQLite multi-process locking makes DB access safe; the registration self-heals; flock coordinates `cli.json` edits (same inode via the shared volume). Guidance: one active session per volume set; use `--ephemeral` for a throwaway second session.
- **[Risk] Spec drift remains in cli-help, package-managers, external-cli-tools, multi-workspace-mounts, gh-auth-proxy (claude-flavoured base content).** → Mitigation: separate spec-modernisation follow-up; this change fixes the two capabilities the upgrade touches.

## Migration Plan

1. Land the package rename + pin refresh; build; run the smoke matrix.
2. Existing `opencode-root`/`opencode-home` volumes work unchanged; the first v2 run imports `auth.json` credentials and writes `cli.json` (auto-migrated from any persisted `tui.json`).
3. Rollback: re-pin `OPENCODE_VERSION` to the last 1.x (`1.19.5`) and rebuild — the volumes remain compatible (v1 reads the same paths; the v2 database is ignored by v1).

## Open Questions

- None blocking. (Whether to pin 2.2.0 now vs 2.1.2 was an operator decision; both are recorded in D2.)
