# Tasks

## 1. Distribution switch to @opencode/cli

- [x] 1.1 Switch the Dockerfile npm install from `opencode-ai` to `@opencode/cli` and update the explicit postinstall path to `$(npm root -g)/@opencode/cli/postinstall.mjs` — verified the published 2.2.0 package ships the same per-arch optional-dep + `postinstall.mjs` shape (registry metadata + local `--ignore-scripts` install + explicit postinstall run producing a working binary).
- [x] 1.2 Switch the `update_pins.py` tool registry entry to `@opencode/cli` — verified `uv run update_pins.py --pin opencode=2.2.0` resolves and writes `pins/opencode.env`.
- [x] 1.3 Refresh pins: `OPENCODE_VERSION=2.2.0` (override, soak bypassed) — verified `pins/opencode.env` diff is exactly the version bump; routine soak-gated bumps to other tools reviewed separately.

## 2. Image environment

- [x] 2.1 Remove `OPENCODE_EXPERIMENTAL_AGENT_TEAMS=1` from the Dockerfile ENV — verified no reference exists in OpenCode 1.x (1.18.16/1.19.5) or 2.x sources.
- [x] 2.2 Keep `OPENCODE_DISABLE_AUTOUPDATE=1` — verified v2 still honours it (`packages/cli/src/services/updater.ts` update-check guard).
- [x] 2.3 Keep `IS_SANDBOX=1` — verified still documented as the legacy `HOST_UID=0` safety net in `README.md`.

## 3. CI contract

- [x] 3.1 Update the `opencode --version` pin-match assertion in `.github/workflows/ci.yml` to expect `opencode v<version>` — verified against a locally installed `@opencode/cli@2.2.0` (`opencode --version` → `opencode v2.2.0`).

## 4. Entrypoint hardening for the v2 background service

- [x] 4.1 Filter `No such file or directory` in the entrypoint chown walk — verified with a simulated vanishing-file race that benign ENOENT/EROFS lines are dropped and genuine errors still surface; `bash -n entrypoint.sh` passes.

## 5. Specs

- [x] 5.1 Write delta specs for `host-config-parity` and `persistent-session-storage` — verified with `openspec validate`.
- [x] 5.2 Sync the deltas into the main specs — verified the two main specs describe OpenCode 2 reality (config paths, seed file, v1-schema acceptance, SQLite session store, service self-healing, ENOENT tolerance) and `openspec validate --specs` passes.

## 6. Archive stale pre-rename changes

- [x] 6.1 Verify the six active changes are implemented in code (wrapper `--help`, `openspec` CLI in image, `--registry`, `--tfe`, `update_pins.py`, `.git/config` overlay) — verified each feature exists in `run.sh` / `Dockerfile` / `update_pins.py`.
- [x] 6.2 Archive all six with spec sync skipped (deltas are claude-flavoured and partly superseded by the gh-auth-proxy sidecar) — verified `openspec list` shows no remaining active changes.

## 7. Verification

- [x] 7.1 Unit tests — `python3 -m unittest discover -s tests` passes (47 tests).
- [x] 7.2 Supply-chain checks — `npm audit signatures` passes for `@opencode/cli@2.2.0` in a scratch dir (3 packages, verified registry signatures + attestations).
- [x] 7.3 Image build + smoke — `docker build -t opencode:local .` succeeds; `opencode --version` prints `opencode v2.2.0`; smoke cell (warm volume, settings seed) passes. (Run on the host.)
- [x] 7.4 Background-service recovery — `opencode debug paths` / `opencode service status` against the warm named volumes behave per spec (stale registration self-heals; per-container loopback). (Run on the host.)

## 8. Change lifecycle

- [x] 8.1 Verify the change against its specs (all requirements have implementation evidence, all tasks complete) — `openspec validate` passes.
- [x] 8.2 Archive `upgrade-opencode-v2` — verified the change lands in `openspec/changes/archive/` and the main specs carry the synced requirements.
