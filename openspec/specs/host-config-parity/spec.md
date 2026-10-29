# host-config-parity

## Purpose

Make the container feel like the user's host OpenCode setup: same skills, agents, commands, prompts, global instructions, and a container-specific `opencode.docker.json` when the user provides one — without copying macOS-only configuration or host-filesystem paths that would misfire inside the Linux container.

The host config directory defaults to `~/.config/opencode` but is configurable via `--opencode-dir=PATH` or the `OPENCODE_DOCKER_CONFIG_DIR` env var. This supports users who maintain multiple OpenCode profiles (e.g. one for API key usage, one for a subscription), each with its own config directory.

## Requirements

### Requirement: Configurable host config directory

`run.sh` SHALL read all host config items from a single base directory. The base directory defaults to `~/.config/opencode` and MAY be overridden with `--opencode-dir=PATH` (flag) or `OPENCODE_DOCKER_CONFIG_DIR` (env var). When both are provided, the flag takes precedence.

#### Scenario: Alternate config dir is used

- **GIVEN** `~/.config/opencode-work/` contains a `commands/` directory with custom slash commands
- **WHEN** user runs `opencode-docker --opencode-dir=~/.config/opencode-work ~/repo`
- **THEN** `/root/.config/opencode/commands/` in the container contains the commands from `~/.config/opencode-work/commands/`

#### Scenario: Env var sets the config dir

- **GIVEN** `OPENCODE_DOCKER_CONFIG_DIR=~/.config/opencode-work` is set in the environment
- **WHEN** user runs `opencode-docker ~/repo`
- **THEN** config items are loaded from `~/.config/opencode-work/` as if `--opencode-dir=~/.config/opencode-work` had been passed

### Requirement: Bind-mount host OpenCode config items

`run.sh` SHALL dereference and bind-mount the following host items (when present) read-only into the container at the equivalent `/root/.config/opencode/` path: `agents/`, `skills/`, `commands/`, `prompts/`, and `AGENTS.md`. When the host provides `statusline-command.sh`, `run.sh` SHALL additionally mount a generated wrapper at `/root/.config/opencode/statusline-command.sh` that prefixes the active opt-in tag. Symlinks MUST be resolved at two levels:

1. **Top-level directory symlink**: if `$OPENCODE_DOCKER_CONFIG_DIR/commands` is itself a symlink, `run.sh` SHALL resolve it to its real path before staging, so the copy source is always a real directory.
2. **Internal symlinks**: `run.sh` SHALL use `cp -RL` to dereference all symlinks within the directory tree during staging, so targets outside the mount root still resolve inside the container.

OpenCode 2 discovers `agents/`, `commands/`, `skills/`, and the global `AGENTS.md` from the global config directory, and translates v1-format agent/command frontmatter automatically. The `prompts/` mount and the `statusline-command.sh` wrapper are inert under OpenCode (upstream has no prompts-directory or statusline-command feature); they are mounted for forward compatibility only and SHALL NOT be relied on to change agent behaviour.

The stage directory MUST reside under `$HOME` (e.g. `$HOME/.cache/opencode-docker/host.XXXXXX`). Colima's default mount config exposes only `$HOME` (`/Users/$USER`) to its Linux VM — `/tmp` and `$TMPDIR` are NOT shared. A bind-mount sourced from outside `$HOME` starts without error but silently yields an empty mountpoint inside the container under Colima. Docker Desktop also shares `$HOME` (under `/Users`), so `$HOME` is the one stage location that works on both runtimes.

Host-filesystem hooks (settings `hooks`, script paths outside the mounts) are intentionally NOT carried over — host hooks exist to protect the host filesystem, which Docker already isolates.

#### Scenario: Skills via symlinks resolve in container

- **GIVEN** `~/.config/opencode/skills/create-team` is a symlink to `~/repos/shared-config/skills/create-team`
- **WHEN** user runs `opencode-docker`
- **THEN** `/root/.config/opencode/skills/create-team/` in the container contains the skill files (not a dangling symlink)

#### Scenario: Top-level directory symlink resolves in container

- **GIVEN** `~/.config/opencode-work/commands` is a symlink to `~/opencode-config/commands`
- **WHEN** user runs `opencode-docker --opencode-dir=~/.config/opencode-work ~/repo`
- **THEN** `/root/.config/opencode/commands/` in the container contains the files from `~/opencode-config/commands/`

#### Scenario: Custom agents are discovered by OpenCode 2

- **GIVEN** `~/.config/opencode/agents/reviewer.md` defines a custom agent (v1 frontmatter with `mode: subagent`)
- **WHEN** the container launches OpenCode 2
- **THEN** the agent appears in the agent list (e.g. `opencode debug agents` shows `reviewer`)

#### Scenario: Statusline and prompts mounts are inert under OpenCode

- **GIVEN** the host has `~/.config/opencode/statusline-command.sh` and `~/.config/opencode/prompts/`
- **WHEN** user runs `opencode-docker` and OpenCode 2 starts
- **THEN** the wrapper script and prompts directory are mounted read-only under `/root/.config/opencode/`
- **AND** OpenCode does not execute the statusline script or load the prompts directory (no such upstream features)

### Requirement: Container-specific settings file

When `$OPENCODE_DOCKER_CONFIG_DIR/opencode.docker.json` exists, `run.sh` SHALL bind-mount it read-only at the seed path `/run/opencode-docker/opencode.json`, and `entrypoint.sh` SHALL copy the seed to `/root/.config/opencode/opencode.json` at container start. The container-side `opencode.json` MUST be a regular file, not a mountpoint: OpenCode persists settings by renaming a tmp file over `opencode.json`, and `rename()` over a mountpoint fails with `EBUSY`, which would break every in-session settings change. In-session changes therefore save successfully, last for that container run, and are overwritten from the host file on the next start; nothing is ever written back to the host. When absent, no settings file is seeded and any `opencode.json` already in the persistent home volume is left as-is. The regular host `opencode.json` is never forwarded automatically — users maintain `opencode.docker.json` explicitly to prevent silent drift between host and container behaviour.

#### Scenario: Container uses dedicated settings file

- **GIVEN** `~/.config/opencode/opencode.docker.json` contains `{"autoupdate": false}`
- **WHEN** user runs `opencode-docker`
- **THEN** `/root/.config/opencode/opencode.json` in the container is a writable copy of that file

#### Scenario: In-session settings change saves without EBUSY

- **GIVEN** the container started with a seeded `/root/.config/opencode/opencode.json`
- **WHEN** OpenCode renames a tmp file over `/root/.config/opencode/opencode.json` (e.g. the user changes a setting in-session)
- **THEN** the rename succeeds and the change applies for the rest of the run
- **AND** the host `opencode.docker.json` is unchanged
- **AND** the next container start re-seeds `opencode.json` from the host file

#### Scenario: Alternate config dir with settings.docker.json

- **GIVEN** `~/.config/opencode-work/opencode.docker.json` exists (the OpenCode successor of Claude Code's `settings.docker.json`)
- **WHEN** user runs `opencode-docker --opencode-dir=~/.config/opencode-work ~/repo`
- **THEN** `/root/.config/opencode/opencode.json` in the container is a copy of `~/.config/opencode-work/opencode.docker.json`

#### Scenario: No settings file

- **GIVEN** `opencode.docker.json` does not exist in the config dir
- **WHEN** user runs `opencode-docker`
- **THEN** the container starts without a host-derived `opencode.json` seed and OpenCode uses defaults (or whatever a previous run persisted in the home volume)

### Requirement: IS_SANDBOX env var retained for the root fall-through path

The image SHALL set `IS_SANDBOX=1`. In steady state the entrypoint drops the container to the host UID before exec'ing opencode, so no root-user permission check triggers and the variable is not load-bearing; it is retained only for the legacy `HOST_UID=0` fall-through path where the entrypoint does not drop privileges. The container narrows blast radius compared to running `opencode --auto` on the host, but is not a full sandbox — see the threat model in `README.md`.

#### Scenario: --auto launches without a root refusal error

- **WHEN** user runs `opencode-docker --auto ~/repo`
- **THEN** `opencode --auto` launches without a root-user refusal error

### Requirement: OpenCode 1 config schema is accepted

OpenCode 2 SHALL accept a seeded `opencode.json` written in the OpenCode 1 schema, normalising supported v1 fields in memory without rewriting the source file. Supported mappings include `permission` (object keyed by tool) to the v2 ordered `permissions` array (with the `bash` → `shell` action rename), `autoupdate: false` to `update: "disable"`, and the singular `agent`/`command`/`provider` maps to their v2 plural forms. Fields with no v2 equivalent are ignored with a warning.

#### Scenario: v1-schema seed takes effect

- **GIVEN** `opencode.docker.json` contains `{"autoupdate": false, "permission": {"edit": "ask", "bash": "ask"}}`
- **WHEN** the container launches OpenCode 2 and the user inspects the effective configuration (e.g. `opencode debug config`)
- **THEN** the effective configuration shows `update: "disable"` and `permissions` entries for `edit` and `shell` with effect `ask`
- **AND** the seeded file on disk is unchanged

#### Scenario: v2-native schema also accepted

- **GIVEN** `opencode.docker.json` contains v2-native fields (`update`, a `permissions` array, `agents`)
- **WHEN** the container launches OpenCode 2
- **THEN** the settings take effect as written
