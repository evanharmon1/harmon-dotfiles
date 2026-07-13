#!/usr/bin/env bash
# Render the complete chezmoi source without touching the real home directory.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

chezmoi apply \
    --dry-run \
    --no-tty \
    --refresh-externals=never \
    --source "$repo_root" \
    --destination "$tmp_dir/home"

echo "chezmoi source render OK (isolated dry run)"
