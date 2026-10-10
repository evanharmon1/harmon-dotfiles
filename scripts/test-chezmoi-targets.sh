#!/usr/bin/env bash
# Assert which Brewfiles chezmoi deploys, without touching $HOME (#117).
#
# `.chezmoiignore` patterns match TARGET paths, so ignoring the repo's own
# toolchain Brewfile while it was named `Brewfile` also swallowed
# `private_Brewfile` (same target, ~/Brewfile). The toolchain file is now the
# dot-prefixed `.Brewfile`, which chezmoi never treats as a source target.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

if ! command -v chezmoi >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
        fail "chezmoi is not installed in CI, so the managed-target checks cannot run"
    fi
    echo "    chezmoi not installed; skipping the Brewfile target checks"
    exit 0
fi

test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/home"
: >"$test_tmp/chezmoi.toml"

cz() {
    chezmoi --source "$repo" --destination "$test_tmp/home" \
        --config "$test_tmp/chezmoi.toml" \
        --persistent-state "$test_tmp/state.boltdb" "$@"
}

echo "==> ~/Brewfile is a managed target and the repo toolchain file is not"
managed="$(cz managed --path-style=relative)"
printf '%s\n' "$managed" | grep -qx 'Brewfile' ||
    fail "Brewfile is not a managed target (does .chezmoiignore match 'Brewfile' again?)"
printf '%s\n' "$managed" | grep -qx '\.Brewfile' &&
    fail ".Brewfile (the repo toolchain file) must not be deployed"

echo "==> the deployed ~/Brewfile is private_Brewfile"
cz cat "$test_tmp/home/Brewfile" | cmp -s - "$repo/private_Brewfile" ||
    fail "chezmoi renders ~/Brewfile differently from private_Brewfile"

echo "PASS: chezmoi deploys private_Brewfile as ~/Brewfile and never .Brewfile"
