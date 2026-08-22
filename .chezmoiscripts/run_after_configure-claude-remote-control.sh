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
# Never fails an apply: every failure path warns and exits 0. No `set -e` —
# each step that can fail is guarded explicitly so a full disk or a read-only
# directory degrades to a warning instead of aborting `chezmoi apply`.
set -uo pipefail

config_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
tmp=""

warn() {
    echo "==> Warning: $*" >&2
}

cleanup() {
    [ -n "$tmp" ] && rm -f "$tmp"
}
trap cleanup EXIT

# GNU and BSD stat disagree on flags, and the order matters: GNU `stat -f` is
# --file-system and prints a report to stdout before failing, so probing the
# BSD form first on Linux yields multi-line garbage. BSD `stat -c` fails with
# no stdout, so try the GNU form first and fall back to BSD.
file_mode() {
    stat -L -c '%a' "$1" 2>/dev/null || stat -L -f '%Lp' "$1" 2>/dev/null || echo 600
}

# inode:mtime:size of the file behind the path (same dialect ordering).
fingerprint() {
    stat -L -c '%i:%Y:%s' "$1" 2>/dev/null || stat -L -f '%i:%m:%z' "$1" 2>/dev/null || echo "unknown"
}

if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found; skipping Claude Remote Control setup for $config_file"
    exit 0
fi

# A symlinked ~/.claude.json is a real layout (harmon-init's devcontainers link
# it into a persisted volume). Rename-in-place would replace the link with a
# regular file, so operate on the resolved target instead.
if [ -L "$config_file" ]; then
    if ! resolved="$(readlink -f "$config_file" 2>/dev/null)" || [ -z "$resolved" ]; then
        warn "$config_file is a symlink that cannot be resolved; leaving it untouched"
        exit 0
    fi
    config_file="$resolved"
fi
if [ -e "$config_file" ] && [ ! -f "$config_file" ]; then
    warn "$config_file exists but is not a regular file; leaving it untouched"
    exit 0
fi

# Absent file: feed `{}` through the same write-temp-then-rename path below, so
# a first apply can never leave a partial file behind. Existing file: it must
# parse — a corrupt file is left alone rather than overwritten.
if [ -f "$config_file" ]; then
    if ! jq empty "$config_file" >/dev/null 2>&1; then
        warn "$config_file is not valid JSON; leaving it untouched"
        exit 0
    fi
    # Boolean true only: a string "true" is not what Claude Code reads.
    if jq -e '.remoteControlAtStartup == true' "$config_file" >/dev/null 2>&1; then
        exit 0
    fi
    # Preserve the existing mode across the atomic replace: mktemp creates 0600
    # and `mv` carries the temp file's mode over, so a more permissive original
    # would silently change.
    mode="$(file_mode "$config_file")"
    # Claude Code rewrites this file while running. Fingerprint it (inode,
    # mtime, size) before reading and re-check immediately before the rename:
    # if it changed underneath us, skip rather than overwrite newer state —
    # the next apply retries. This narrows the lost-update window to the
    # instant between the check and the rename; it cannot close it, since
    # Claude Code exposes no lock to take.
    before="$(fingerprint "$config_file")"
    jq_args=('.remoteControlAtStartup = true' "$config_file")
else
    mode=600
    before=""
    jq_args=(-n '{remoteControlAtStartup: true}')
fi

config_dir="$(dirname "$config_file")"
if ! mkdir -p "$config_dir"; then
    warn "cannot create $config_dir; leaving Claude Remote Control unset"
    exit 0
fi
if ! tmp="$(mktemp "$config_dir/.claude.json.XXXXXX")"; then
    tmp=""
    warn "cannot create a temporary file in $config_dir; leaving $config_file unchanged"
    exit 0
fi

if ! jq "${jq_args[@]}" >"$tmp" 2>/dev/null || ! chmod "$mode" "$tmp"; then
    warn "failed to update $config_file; leaving existing value unchanged"
    exit 0
fi
if [ -n "$before" ] && [ "$(fingerprint "$config_file")" != "$before" ]; then
    warn "$config_file changed while updating it (another writer is active); leaving it for the next apply"
    exit 0
fi
if ! mv "$tmp" "$config_file"; then
    warn "failed to update $config_file; leaving existing value unchanged"
    exit 0
fi
tmp=""
echo "==> Enabled Claude Code Remote Control (remoteControlAtStartup=true) in $config_file"
