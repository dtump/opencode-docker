# Spec Delta

## MODIFIED Requirements

### Requirement: Sessions persist across container runs

All OpenCode session data, credentials, and project records SHALL live in named Docker volumes that survive `--rm` container lifecycles: `opencode-root` mounted at `/root` and `opencode-home` mounted at `/root/.config/opencode`. OpenCode 2 stores sessions in a SQLite database at `/root/.local/share/opencode/opencode.db`; provider credentials live in the same data tree.

#### Scenario: Sessions survive exit

- **WHEN** the user exits an OpenCode session and relaunches the container
- **THEN** `opencode --continue` offers the prior session for the current project
- **AND** `opencode --session <id>` resumes it

### Requirement: Single shared store across workspaces

Sessions from every workspace MUST live under the same `/root` tree (one `opencode-root` volume) so `opencode --continue` lists them together.

#### Scenario: Cross-workspace listing

- **WHEN** the user runs `opencode --continue` in any mounted workspace
- **THEN** sessions from every workspace used in prior runs appear

### Requirement: Ephemeral mode opts out of persistence

`run.sh` SHALL support a `--ephemeral` flag that skips the `opencode-root` and `opencode-home` named-volume mounts. In this mode no OAuth token, `gh` login, shell history, or session history persist between container runs. Intended for one-shot or untrusted-workspace sessions.

#### Scenario: --ephemeral leaves no trace

- **GIVEN** a prior run completed with session history in the `opencode-root` volume
- **WHEN** user runs `opencode-docker --ephemeral ~/repo`
- **THEN** `/root/.local/share/opencode/` starts empty inside the new container
- **AND** on exit, no writes under `/root/` are retained in either named volume

## ADDED Requirements

### Requirement: Provider credentials carry across runs

Provider and OAuth credentials SHALL persist across container runs via the named volumes. OpenCode 2 imports the legacy OpenCode 1 credential store (`/root/.local/share/opencode/auth.json`) into its database on first run after the upgrade, so provider logins made under OpenCode 1 keep working under OpenCode 2.

#### Scenario: Credentials survive the v1 to v2 upgrade

- **GIVEN** an `opencode-root` volume containing an OpenCode 1 `auth.json` with a provider credential
- **WHEN** the user launches a container running OpenCode 2 for the first time on that volume
- **THEN** the provider remains authenticated (no re-login required)

### Requirement: OpenCode 1 conversation history does not migrate

OpenCode 2 SHALL start with a fresh session database and SHALL NOT present OpenCode 1 conversation history as resumable sessions. Only credentials are imported from the v1 store; session history from v1 runs is not migrated.

#### Scenario: v1 history is not resumable after upgrade

- **GIVEN** an `opencode-root` volume containing OpenCode 1 session history (file-based storage under `/root/.local/share/opencode/`)
- **WHEN** the user launches OpenCode 2 on that volume and runs `opencode --continue`
- **THEN** no v1 sessions are listed
- **AND** provider credentials from the same volume still work

### Requirement: Background service registration self-heals across containers

OpenCode 2 runs a per-user background service registered at `/root/.local/state/opencode/service.json` (loopback URL plus basic-auth password), with the session database and logs under `/root/.local/share/opencode/`. The registration persists in the `opencode-root` volume but is only reachable from the container that created it. A stale registration left by a dead container SHALL be detected (the recorded loopback health check fails) and replaced by a fresh service on the next command, without user action and without manual cleanup.

#### Scenario: Stale registration is replaced on next run

- **GIVEN** a prior container was killed, leaving `service.json` pointing at a dead loopback address
- **WHEN** the user starts a new container on the same volumes and runs any OpenCode command
- **THEN** a fresh background service starts and the command succeeds

#### Scenario: Registration is not shared across concurrent containers

- **GIVEN** one container's OpenCode 2 background service is running on the shared volumes
- **WHEN** a second container starts on the same volumes and queries `opencode service status`
- **THEN** the query reports the registered service as unreachable/stopped from the second container's loopback
- **AND** on-demand commands in the second container start their own service

### Requirement: Volume ownership fixup tolerates concurrent containers

The entrypoint's ownership fixup walk over `/root` SHALL NOT fail or warn when transient OpenCode 2 files — flock lock directories under `/root/.local/state/opencode/locks/`, the `service.json` registration, SQLite `-wal`/`-shm` sidecars — vanish mid-walk while a concurrent container's service is running on the same volumes. A file that vanishes mid-walk needs no ownership change. Genuine chown errors (anything other than `EROFS` and `ENOENT`) SHALL still surface as `entrypoint: WARN` lines.

#### Scenario: Concurrent container start produces no spurious warning

- **GIVEN** one container's OpenCode 2 background service is running on the shared `opencode-root` volume
- **WHEN** a second container starts on the same volumes
- **THEN** the entrypoint completes without an `entrypoint: WARN chown:` line caused by vanishing transient files
