#!/usr/bin/env bash
# Enable Claude Code Remote Control for local sessions (issue #67).
#
# Sets `remoteControlAtStartup: true` in ~/.claude.json so every `claude`
# session registers with claude.ai/code automatically — the same invariant the
# devcontainers assert in harmon-init's .devcontainer/scripts/post-start-common.sh,
# mirrored here for the host machine.
#
# Why a script instead of a managed file: ~/.claude.json is Claude Code's own
# runtime state (startup counters, per-project history, tips, OAuth bookkeeping)
# and is rewritten constantly. Managing it with chezmoi would clobber that state
# on every apply, so this merges a single key into whatever is already there.
#
# Why `run_after_` and not `run_onchange_`: the invariant is "every apply
# re-asserts the key", not "re-run when this script changes" — Claude Code can
# flip the value back at any time, and an onchange script would not notice.
#
# Never fails an apply: every failure path warns and exits 0.
set -euo pipefail

config_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "==> Warning: jq not found; skipping Claude Remote Control setup for $config_file" >&2
    exit 0
fi

if [ ! -f "$config_file" ]; then
    mkdir -p "$(dirname "$config_file")"
    (
        umask 077
        echo '{}' >"$config_file"
    )
    chmod 600 "$config_file"
fi

if ! jq empty "$config_file" >/dev/null 2>&1; then
    echo "==> Warning: $config_file is not valid JSON; leaving it untouched" >&2
    exit 0
fi

if [ "$(jq -r '.remoteControlAtStartup // false' "$config_file" 2>/dev/null)" = "true" ]; then
    exit 0
fi

# Preserve the existing mode across the atomic replace: mktemp creates 0600 and
# `mv` carries the temp file's mode over, so a more permissive original would
# silently change. BSD and GNU stat spell the query differently.
mode="$(stat -f '%Lp' "$config_file" 2>/dev/null || stat -c '%a' "$config_file" 2>/dev/null || echo 600)"

tmp="$(mktemp "$(dirname "$config_file")/.claude.json.XXXXXX")"
if jq '.remoteControlAtStartup = true' "$config_file" >"$tmp"; then
    chmod "$mode" "$tmp"
    mv "$tmp" "$config_file"
    echo "==> Enabled Claude Code Remote Control (remoteControlAtStartup=true) in $config_file"
else
    rm -f "$tmp"
    echo "==> Warning: failed to update $config_file; leaving existing value unchanged" >&2
    exit 0
fi
