#!/usr/bin/env bash
# test-render-templates.sh — regression test for scripts/render-templates.sh
# (issue #49): the clean tree renders, and each kind of break is caught and
# named. Run via `task test:render-templates`.
#
# Hermetic: every case works on a throwaway copy of the source tree; the real
# tree is never modified.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
renderer="$repo/scripts/render-templates.sh"
bash_bin="$(command -v bash)"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

# The renderer skips locally without chezmoi; in CI it fails. Mirror
# test-ai-config.sh: the cases that need a real chezmoi skip locally, and a
# missing chezmoi in CI is a broken runner. The no-chezmoi cases below do not
# need chezmoi and always run.
have_chezmoi=1
if ! command -v chezmoi >/dev/null 2>&1; then
    have_chezmoi=0
    if [ "${CI:-}" = "true" ]; then
        fail "chezmoi is not installed in CI, so the render regression tests cannot run"
    fi
    echo "SKIP: chezmoi is not installed; render cases skipped"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# fresh_copy <name>: a git work tree holding the current (including
# uncommitted) source, so the renderer's `git ls-files` sees the same files.
fresh_copy() {
    local dir="$tmp/$1"
    mkdir -p "$dir"
    git -C "$repo" ls-files -z --cached --others --exclude-standard |
        while IFS= read -r -d '' f; do
            [ -e "$repo/$f" ] || [ -L "$repo/$f" ] && printf '%s\0' "$f"
        done |
        (cd "$repo" && xargs -0 tar -cf -) |
        tar -xf - -C "$dir"
    git -C "$dir" init -q
    printf '%s' "$dir"
}

# expect_fail <case> <must-name> <dir>: the renderer exits non-zero and its
# output names <must-name>.
expect_fail() {
    local name="$1" needle="$2" dir="$3" out rc=0
    out="$("$renderer" "$dir" 2>&1)" || rc=$?
    [ "$rc" -ne 0 ] || fail "$name: renderer passed a broken tree: $out"
    case "$out" in
    *"$needle"*) ;;
    *) fail "$name: output does not name '$needle': $out" ;;
    esac
}

# Paths with no chezmoi on PATH (an empty directory), run by absolute bash.
mkdir "$tmp/empty-bin"
src="$(fresh_copy nochezmoi)"
rc=0
out="$(env -i PATH="$tmp/empty-bin" "$bash_bin" "$renderer" "$src" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "without chezmoi, locally, the renderer must skip: $out"
case "$out" in *SKIP*) ;; *) fail "skip must say so: $out" ;; esac
rc=0
out="$(env -i PATH="$tmp/empty-bin" CI=true "$bash_bin" "$renderer" "$src" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "without chezmoi, in CI, the renderer must fail: $out"

if [ "$have_chezmoi" -eq 1 ]; then
    # Clean tree passes.
    src="$(fresh_copy clean)"
    "$renderer" "$src" >/dev/null || fail "clean tree must render"

    # A broken template is named.
    src="$(fresh_copy broken-template)"
    printf '\n{{ if }}\n' >>"$src/private_dot_zshrc.tmpl"
    expect_fail "broken template" "private_dot_zshrc.tmpl" "$src"

    # A broken .chezmoiignore is named.
    src="$(fresh_copy broken-ignore)"
    printf '\n{{ if }}\n' >>"$src/.chezmoiignore"
    expect_fail "broken .chezmoiignore" ".chezmoiignore" "$src"

    # Templates that are not named *.tmpl are still evaluated: chezmoi treats
    # modify_ templates and .chezmoitemplates partials as templates, so the
    # whole-state check must catch a break in any of them.
    for f in private_dot_claude/modify_private_settings.json \
        private_dot_codex/modify_private_harmon-local.config.toml \
        private_dot_gemini/antigravity-cli/modify_private_settings.json \
        .chezmoitemplates/claude-settings/enforced.json \
        .chezmoitemplates/claude-settings/seeded.json; do
        src="$(fresh_copy "nontmpl-${f##*/}")"
        printf '\n{{ if }}\n' >>"$src/$f"
        expect_fail "broken $f" "${f##*/}" "$src"
    done

    # A missing .chezmoiignore is a failure, not a skip.
    src="$(fresh_copy missing-ignore)"
    rm -f "$src/.chezmoiignore"
    expect_fail "missing .chezmoiignore" ".chezmoiignore" "$src"

    # An untracked, non-ignored template is rendered too.
    src="$(fresh_copy untracked)"
    printf '{{ if }}\n' >"$src/dot_untracked.tmpl"
    expect_fail "untracked template" "dot_untracked.tmpl" "$src"

    # Each side of the render-time branches is exercised: a *render-time*
    # failure (`fail`, not a parse error, which every variant would hit) placed
    # only in one branch must still be caught. If a variant stopped taking a
    # branch, the clean tree would still pass, so these are the proof.
    src="$(fresh_copy gh-branch)"
    sed -i.bak 's|^\[credential "https://gist.github.com"\]|{{ fail "boom" }}\n&|' \
        "$src/dot_config/private_git/config.tmpl"
    rm -f "$src/dot_config/private_git/config.tmpl.bak"
    grep -q 'fail "boom"' "$src/dot_config/private_git/config.tmpl" || fail "gh-branch mutation did not apply"
    expect_fail "gh-present branch" "config.tmpl" "$src"

    # The container, non-darwin and non-linux branches of .chezmoiignore.
    local_branch_case() {
        local name="$1" anchor="$2" dir
        dir="$(fresh_copy "$name")"
        sed -i.bak "s|^${anchor}\$|{{ fail \"boom\" }}\n&|" "$dir/.chezmoiignore"
        rm -f "$dir/.chezmoiignore.bak"
        grep -q 'fail "boom"' "$dir/.chezmoiignore" || fail "$name mutation did not apply"
        expect_fail "$name" ".chezmoiignore" "$dir"
    }
    local_branch_case container-branch '\.config/git/config'
    local_branch_case non-darwin-branch 'Library/\*\*'
    local_branch_case non-linux-branch '\.config/ghostty/\*\*'

    # A misnamed run script (no run_ prefix): chezmoi itself rejects it.
    src="$(fresh_copy bad-script)"
    printf '#!/bin/sh\n' >"$src/.chezmoiscripts/configure-extra.sh"
    expect_fail "misnamed run script" "configure-extra.sh" "$src"

    # A run script chezmoi silently does not pick up (here: ignored) is named.
    # This is the case the `managed --include=scripts` assertion exists for.
    src="$(fresh_copy ignored-script)"
    printf '\n.chezmoiscripts/*\n' >>"$src/.chezmoiignore"
    expect_fail "ignored run script" "run_after_configure-claude-remote-control.sh" "$src"

    # A valid run script in a subdirectory of .chezmoiscripts/ is picked up
    # under that subdirectory, not rejected (review round 1).
    src="$(fresh_copy nested-script)"
    mkdir -p "$src/.chezmoiscripts/sub"
    printf '#!/bin/sh\n' >"$src/.chezmoiscripts/sub/run_after_nested.sh"
    out="$("$renderer" "$src" 2>&1)" || fail "a nested run script must be accepted: $out"

    # No .chezmoiscripts dir content is fine.
    src="$(fresh_copy no-scripts)"
    rm -rf "$src/.chezmoiscripts"
    "$renderer" "$src" >/dev/null || fail "a tree without run scripts must render"
fi

echo "test-render-templates: ok"
