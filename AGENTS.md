# OpenCode Agents Configuration

This file documents the OpenCode configuration for the opencode-docker project.

## Project Overview

`opencode-docker` is a hardened Docker wrapper for OpenCode that provides:
- Isolated workspace access via bind mounts
- Credential opt-in mechanisms for AWS, GitHub, GitLab, and Terraform Cloud
- GitHub auth proxy sidecar for secure token handling
- Private package registry support
- File ownership preservation (host UID/GID mapping)
- Security hardening via capability dropping and no-new-privileges

## Agent Configuration

### Primary Agent
The main OpenCode agent runs inside the container with access to mounted workspaces and opted-in credentials.

### Config Directory
- **Host:** `~/.config/opencode/`
- **Container:** `/root/.config/opencode/`

Mounted items from host config:
- `agents/` - Custom agent definitions
- `skills/` - Custom skills
- `commands/` - Slash commands
- `prompts/` - Custom prompts
- `AGENTS.md` - Global preferences
- `opencode.docker.json` - Container-specific OpenCode config (copied to `opencode.json`)

### Settings
Container-specific settings are managed via `opencode.docker.json`, which is copied to `opencode.json` in the container at startup. This allows in-session config changes to persist for the container's lifetime while being re-seeded from the host on each start.

See `examples/opencode.docker.json` for a starting configuration.

## Security Model

### Protected
- Host filesystem outside passed workspaces
- Host `~/.aws/credentials` (long-lived keys)
- Host credential directories (read-only when opted in)

### Exposed (per session, when opted in)
- Workspace directories (read-write unless `--ro`)
- Short-lived AWS SSO bearer tokens
- GitHub tokens (via proxy sidecar or direct forwarding)
- GitLab tokens
- Terraform Cloud tokens
- Private registry configuration files

### Persistent State
Named volumes carry state across runs (unless `--ephemeral`):
- `opencode-root` - `/root` (OAuth tokens, shell history)
- `opencode-home` - `/root/.config/opencode` (conversation history, settings)

## Usage Patterns

### Multi-workspace
```bash
opencode-docker ~/repo-a ~/repo-b
```

### Credential Opt-in
```bash
opencode-docker --aws --gh ~/repo
```

### Read-only Review
```bash
opencode-docker --ephemeral --ro ~/untrusted-repo
```

### Split-pane Teams
```bash
opencode-docker --iterm ~/repo  # iTerm2 native panes
opencode-docker --tmux ~/repo   # Plain tmux splits
```

## Customization

Extend the base image with project-specific tooling:
```dockerfile
FROM opencode:local
RUN apt-get install -y my-tool
```

Then use with:
```bash
OPENCODE_DOCKER_IMAGE=my-opencode:local opencode-docker ~/repo
```
