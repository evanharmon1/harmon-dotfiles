#!/usr/bin/env bash
# test-hooks.sh — round-trip the Taskfile targets and Codex adapters shared by
# the Claude/Codex hooks. Guards against the go-task CLI_ARGS
# quoting/injection class of bug, where a valid commit message is silently
# rejected (blocking every commit) or a path with a space is silently skipped.
# Run via `task test:hooks`.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

echo "==> lint:commit-msg:text accepts a valid conventional message"
if ! printf '%s' 'feat: a valid message' | task lint:commit-msg:text >/dev/null 2>&1; then
    fail "lint:commit-msg:text rejected a VALID conventional message"
fi

echo "==> lint:commit-msg:text rejects a non-conventional message"
if printf '%s' 'not a conventional message' | task lint:commit-msg:text >/dev/null 2>&1; then
    fail "lint:commit-msg:text accepted an INVALID message"
fi

echo "==> format:file formats a file, including a path containing a space"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
spaced="$tmpdir/with space.sh"
printf 'f(){\necho hi\n}\n' >"$spaced"
before="$(cat "$spaced")"
if ! task format:file -- "$spaced" >/dev/null 2>&1; then
    fail "format:file errored on a path containing a space"
fi
if [ "$before" = "$(cat "$spaced")" ]; then
    fail "format:file did not reformat a mis-formatted file"
fi

echo "==> hook-delegation targets OK (commit-msg accept/reject, format:file)"

echo "==> Codex apply_patch adapter emits one Claude-style payload per file"
capture="$tmpdir/capture"
mock="$tmpdir/mock-hook.sh"
cat >"$mock" <<'EOF'
#!/usr/bin/env bash
jq -r '.tool_input.file_path' >>"$HOOK_CAPTURE"
EOF
chmod +x "$mock"
export HOOK_CAPTURE="$capture"
printf '%s' '{"cwd":"/tmp/project","tool_input":{"command":"*** Begin Patch\n*** Update File: one.txt\n*** Add File: dir/two.txt\n*** End Patch"}}' |
    bash "$repo/private_dot_codex/hooks/executable_file-payload.sh" "$mock"
printf 'one.txt\ndir/two.txt\n' >"$tmpdir/expected"
cmp -s "$tmpdir/expected" "$capture" ||
    fail "Codex file-payload adapter did not preserve both patch paths"

echo "==> Codex Bash adapter exports the session cwd"
cwd_mock="$tmpdir/cwd-hook.sh"
cat >"$cwd_mock" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$CLAUDE_PROJECT_DIR"
cat >/dev/null
EOF
chmod +x "$cwd_mock"
got="$(printf '%s' '{"cwd":"/tmp/codex-project"}' |
    bash "$repo/private_dot_codex/hooks/executable_claude-compat.sh" "$cwd_mock")"
[ "$got" = "/tmp/codex-project" ] || fail "Codex Bash adapter lost the session cwd"

echo "==> Antigravity adapter preserves a valid non-Git cwd"
agy_capture="$tmpdir/agy-cwd"
agy_mock="$tmpdir/agy-hook.sh"
nongit_cwd="$tmpdir/non-git"
mkdir -p "$nongit_cwd"
cat >"$agy_mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n%s\n' "$CLAUDE_PROJECT_DIR" "$PWD" >"$AGY_CAPTURE"
cat >/dev/null
EOF
chmod +x "$agy_mock"
AGY_CAPTURE="$agy_capture" printf '{"toolCall":{"name":"run_command","args":{"Cwd":"%s","CommandLine":"true"}}}' "$nongit_cwd" |
    AGY_CAPTURE="$agy_capture" bash "$repo/private_dot_gemini/config/executable_agy-adapter.sh" "$agy_mock" PreToolUse >/dev/null
printf '%s\n%s\n' "$nongit_cwd" "$nongit_cwd" >"$tmpdir/agy-expected"
cmp -s "$tmpdir/agy-expected" "$agy_capture" ||
    fail "Antigravity adapter lost a valid non-Git cwd"

echo "==> protect-files scopes Codex config protection to the machine"
protect="$repo/private_dot_claude/hooks/executable_protect-files.sh"
if [[ "$(uname -s)" == Darwin ]] &&
    printf '%s' '{"tool_input":{"file_path":"/private/etc/codex/config.toml"}}' |
    bash "$protect" >/dev/null 2>&1; then
    fail "protect-files allowed the physical macOS system Codex config path"
fi
if printf '%s' '{"tool_input":{"file_path":"codex/config.toml"}}' |
    CLAUDE_PROJECT_DIR=/etc bash "$protect" >/dev/null 2>&1; then
    fail "protect-files allowed a cwd-relative system Codex config path"
fi
if printf '{"tool_input":{"file_path":"%s/.codex/config.toml"}}' "$HOME" |
    bash "$protect" >/dev/null 2>&1; then
    fail "protect-files allowed a direct write to the machine-level Codex config"
fi
if (cd "$HOME" && printf '%s' '{"tool_input":{"file_path":".codex/config.toml"}}' |
    bash "$protect" >/dev/null 2>&1); then
    fail "protect-files allowed a cwd-relative write to the machine-level Codex config"
fi
if ! printf '%s' '{"tool_input":{"file_path":"/tmp/project/.codex/config.toml"}}' |
    bash "$protect" >/dev/null 2>&1; then
    fail "protect-files blocked an ordinary repository-level Codex config"
fi
fake_home="$tmpdir/home"
mkdir -p "$fake_home/.codex" "$tmpdir/project"
touch "$fake_home/.codex/config.toml"
ln -s "$fake_home/.codex/config.toml" "$tmpdir/project/config-link"
if printf '{"tool_input":{"file_path":"%s"}}' "$tmpdir/project/config-link" |
    HOME="$fake_home" bash "$protect" >/dev/null 2>&1; then
    fail "protect-files allowed a symlink write to the machine-level Codex config"
fi
symlink_home="$tmpdir/symlink-home"
mkdir -p "$symlink_home/.codex"
touch "$tmpdir/codex-config-target"
ln -s "$tmpdir/codex-config-target" "$symlink_home/.codex/config.toml"
if printf '{"tool_input":{"file_path":"%s/.codex/config.toml"}}' "$symlink_home" |
    HOME="$symlink_home" bash "$protect" >/dev/null 2>&1; then
    fail "protect-files allowed a direct write through a symlinked machine config"
fi

echo "==> shared Claude/Codex hook adapters OK"
