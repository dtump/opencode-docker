#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Schuberg Philis
#
# Drop from container root to the host user's UID/GID before exec'ing opencode
# so that files written through bind-mounts match host ownership. With
# HOST_UID unset or 0, falls through to the legacy "run as root" behavior so
# the image still works in environments that don't forward the host UID.
set -euo pipefail

HOST_UID="${HOST_UID:-0}"
HOST_GID="${HOST_GID:-0}"

# Seed /root/.config/opencode/opencode.json from the host opencode.docker.json that
# run.sh forwards at the seed path. A copy, not a bind mount at the real path:
# OpenCode persists settings by renaming a tmp file over opencode.json, and
# rename() over a mountpoint fails with EBUSY — a direct single-file mount
# breaks every in-session settings change. The copy lives on the container
# filesystem, so those writes work; they last for this run only and are
# overwritten from the host file on the next start.
# Ownership dance: on a warm volume the dir/file are HOST_UID-owned from a
# prior run's chown walk, and container root has no CAP_DAC_OVERRIDE — take
# ownership (CAP_CHOWN) before writing; the chown walk below hands everything
# back to HOST_UID. rm+cp instead of cp -f for the same reason: overwriting a
# HOST_UID-owned 0600 file in place would be denied.
if [ -f /run/opencode-docker/opencode.json ]; then
mkdir -p /root/.config/opencode
chown root /root/.config/opencode
rm -f /root/.config/opencode/opencode.json
cp /run/opencode-docker/opencode.json /root/.config/opencode/opencode.json
chmod 600 /root/.config/opencode/opencode.json
fi

# GitHub auth-proxy sidecar CA (run.sh --gh with a sidecar active): install
# it into the system trust store so git (libcurl) and gh (Go) trust the
# sidecar's TLS termination for the redirected GitHub hostnames. Must run
# as root, before the UID drop below — update-ca-certificates writes under
# /etc/ssl/certs. Silent when the file is absent (no --gh, --gh-direct, or
# the no-token fallback); a refresh failure is a warning, not fatal, so it
# doesn't block the session over a CA problem the user can't fix here.
if [ -f /usr/local/share/ca-certificates/opencode-docker-gh-proxy.crt ]; then
update-ca-certificates >/dev/null 2>&1 \
  || printf 'entrypoint: WARN update-ca-certificates failed for the gh-auth-proxy CA\n' >&2
fi

if [ "$HOST_UID" = 0 ]; then
exec "$@"
fi

# Synthesize a passwd entry so getpwuid / $HOME / shell expansions resolve
# cleanly inside the container. -o (--non-unique) tolerates a HOST_UID that
# happens to collide with a baked-in Ubuntu system user. HOME=/root is
# deliberate — keeps the existing /root/.config/opencode, /root/.aws, /root/.config
# mount paths intact instead of forcing a layout migration.
# -K UID_MIN=1 overrides the login.defs floor per-call so macOS UIDs (≥501,
# below Ubuntu's default 1000) don't trigger a warning.
if ! getent passwd "$HOST_UID" >/dev/null 2>&1; then
getent group "$HOST_GID" >/dev/null 2>&1 \
    || groupadd -o -g "$HOST_GID" opencode
useradd -o -K UID_MIN=1 -u "$HOST_UID" -g "$HOST_GID" -d /root -s /bin/bash -M -N opencode
fi

# Chown the persistent /root volumes (opencode-root, opencode-home)
# so the dropped-privilege user can write its own HOME. -xdev prunes the
# :ro credential and config bind-mounts under /root on Linux (they have
# distinct st_dev), but Docker Desktop's virtiofs on macOS collapses
# st_dev across bind mounts so the walk descends into them anyway. chown
# on a :ro mount returns EROFS, which would abort the entrypoint under
# set -e — so we capture stderr, drop the expected EROFS lines, and
# surface anything else as a warning. Pruning by /proc/self/mountinfo
# would also skip the *writable* tmpfs masks (which we do want to chown),
# so the post-hoc filter is the simpler-correct option. Two start points
# because /root and /root/.config/opencode are separate volumes. Requires
# CAP_CHOWN to chown to a different UID, and CAP_DAC_READ_SEARCH so
# container root can traverse HOST_UID-owned, mode-0700 directories
# under /root.
chown_errs="$(find /root /root/.config/opencode -xdev -print0 \
  | xargs -0 --no-run-if-empty chown -h "$HOST_UID:$HOST_GID" 2>&1 >/dev/null || true)"
chown_errs="$(grep -v 'Read-only file system' <<<"$chown_errs" || true)"
[ -n "$chown_errs" ] && printf 'entrypoint: WARN chown: %s\n' "$chown_errs" >&2 || true

# runuser uses setresuid()/setresgid() — needs CAP_SETUID and CAP_SETGID
# at this point (we're still UID 0). The kernel clears effective,
# permitted, and ambient caps on the UID→non-zero transition; the bounding
# set retains the setup caps but is inert under `no-new-privileges`. So
# opencode itself runs with no usable capabilities downstream — a stricter
# posture than the previous "root + DAC_OVERRIDE for the entire session"
# model where opencode held DAC_OVERRIDE for its whole lifetime.
exec runuser -u opencode -- "$@"
