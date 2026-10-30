#!/usr/bin/env bash
# test-hooks.sh — round-trip the Taskfile targets and Codex adapters shared by
# the Claude/Codex hooks. Guards against the go-task CLI_ARGS
# quoting/injection class of bug, where a valid commit message is silently
# rejected (blocking every commit) or a path with a space is silently skipped.
# Run via `task test:hooks`.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

# The agy-adapter fixtures below run `git init`/`commit`/`worktree add` in
# throwaway repos. Left unsanitized, a machine with commit.gpgsign=true or a
# global core.hooksPath can make those fixture commits prompt, fail, or fire
# unrelated hooks — and since this suite is part of the required local gate,
# that makes `task test:hooks` unreliable rather than merely the fixture.
# Same isolation scripts/test-worktree.sh uses, for the same reason.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
git_config_count="${GIT_CONFIG_COUNT:-0}"
case "$git_config_count" in
'' | *[!0-9]*) git_config_count=0 ;;
esac
i=0
while [ "$i" -lt "$git_config_count" ]; do
    unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"
    i=$((i + 1))
done
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_ALTERNATE_OBJECT_DIRECTORIES

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "==> lint:commit-msg:text accepts a valid conventional message"
if ! printf '%s' 'feat: a valid message' | task lint:commit-msg:text >/dev/null 2>&1; then
    fail "lint:commit-msg:text rejected a VALID conventional message"
fi

echo "==> lint:commit-msg:text rejects a non-conventional message"
if printf '%s' 'not a conventional message' | task lint:commit-msg:text >/dev/null 2>&1; then
    fail "lint:commit-msg:text accepted an INVALID message"
fi

if command -v shfmt >/dev/null 2>&1; then
    echo "==> format:file formats a file, including a path containing a space"
    spaced="$tmpdir/with space.sh"
    printf 'f(){\necho hi\n}\n' >"$spaced"
    before="$(cat "$spaced")"
    if ! task format:file -- "$spaced" >/dev/null 2>&1; then
        fail "format:file errored on a path containing a space"
    fi
    if [ "$before" = "$(cat "$spaced")" ]; then
        fail "format:file did not reformat a mis-formatted file"
    fi
else
    echo "==> format:file delegation skipped (shfmt unavailable)"
fi

echo "==> hook-delegation targets OK (commit-msg accept/reject, format:file)"

# Commit messages must come from the git invocation, never adjacent commands.
assert_commit_status() {
    local hook="$1" expected="$2" command_text="$3"
    local status=0 output
    output="$(jq -n --arg command "$command_text" --arg cwd "$tmpdir" \
        '{cwd: $cwd, tool_input: {command: $command}}' |
        CLAUDE_PROJECT_DIR="$repo" bash "$hook" 2>&1)" || status=$?
    [ "$status" -eq "$expected" ] ||
        fail "$hook: expected exit $expected, got $status for $command_text: $output"
}

python_before_commit="$(
    cat <<'COMMAND'
python3 - <<'EOF'
import pathlib
print('git commit -m bad message')
EOF
git commit -F msg.txt
COMMAND
)"
heredoc_message="$(
    cat <<'COMMAND'
git commit -m "$(cat <<'EOF'
fix: multiline message

A body with 'quotes' and a second paragraph.
EOF
)"
COMMAND
)"
bad_heredoc_message="$(
    cat <<'COMMAND'
git commit -m "$(cat <<'EOF'
bad message

A body that must not hide the invalid subject.
EOF
)"
COMMAND
)"

unquoted_heredoc_header="$(
    cat <<'COMMAND'
git commit -m "$(cat <<EOF
$TYPE: expanded by the shell
EOF
)"
COMMAND
)"
quoted_heredoc_literals="$(
    cat <<'COMMAND'
git commit -m "$(cat <<'EOF'
feat: add `--flag`

Mentions `x` and $HOME literally.
EOF
)"
COMMAND
)"

continued_commit="$(
    cat <<'COMMAND'
git commit \
-m "bad message"
COMMAND
)"

for commit_hook in \
    "$repo/.claude/hooks/enforce-conventional-commits.sh" \
    "$repo/.devcontainer/config/claude-hooks/enforce-conventional-commits.sh" \
    "$repo/template/.claude/hooks/enforce-conventional-commits.sh" \
    "$repo/template/[% if devcontainer %].devcontainer[% endif %]/config/claude-hooks/enforce-conventional-commits.sh"; do
    [ -f "$commit_hook" ] || continue
    echo "==> conventional commit extraction: $commit_hook"
    printf 'fix: file message\n' >"$tmpdir/msg.txt"
    assert_commit_status "$commit_hook" 0 "$python_before_commit"
    printf 'bad file message\n' >"$tmpdir/msg.txt"
    # -F/--file deliberately delegate to lefthook, even for an invalid file.
    assert_commit_status "$commit_hook" 0 "$python_before_commit"
    assert_commit_status "$commit_hook" 0 'git commit --file msg.txt'
    assert_commit_status "$commit_hook" 0 'git commit --file=msg.txt'
    assert_commit_status "$commit_hook" 0 "$heredoc_message"
    assert_commit_status "$commit_hook" 2 "$bad_heredoc_message"
    assert_commit_status "$commit_hook" 0 "echo 'git commit -m bad'"
    assert_commit_status "$commit_hook" 2 'git commit -m "bad message"'
    assert_commit_status "$commit_hook" 0 'git commit -m "fix: ok"'
    assert_commit_status "$commit_hook" 0 'echo -m "bad message"; git commit --amend --no-edit'
    assert_commit_status "$commit_hook" 0 'git commit -C HEAD'
    assert_commit_status "$commit_hook" 0 'git commit'
    assert_commit_status "$commit_hook" 0 'git commit -m "unterminated'
    assert_commit_status "$commit_hook" 0 'echo -m "bad message"; git commit --message "fix: ok"'
    assert_commit_status "$commit_hook" 2 'git commit --message="bad message"'
    assert_commit_status "$commit_hook" 0 'git commit --message="fix: ok"'
    assert_commit_status "$commit_hook" 2 'git commit -m"bad message"'
    assert_commit_status "$commit_hook" 0 'git commit -m"fix: ok"'
    assert_commit_status "$commit_hook" 2 'git -C /tmp commit -m "bad message"'
    assert_commit_status "$commit_hook" 0 'git log -m "bad message" commit'
    assert_commit_status "$commit_hook" 0 'git commit -- path -m "bad message"'
    assert_commit_status "$commit_hook" 0 "${python_before_commit/-F msg.txt/-m \"fix: ok\"}"
    assert_commit_status "$commit_hook" 2 "${python_before_commit/-F msg.txt/-m \"bad message\"}"
    # Shell command words, Git global options, and clustered message options.
    assert_commit_status "$commit_hook" 2 'git --no-pager commit -m "bad message"'
    assert_commit_status "$commit_hook" 2 'git -P commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git --bare commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git -C . commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git -c user.name=x commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git --super-prefix prefix commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git --exec-path commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'git --exec-path=/tmp commit -m "bad"'
    assert_commit_status "$commit_hook" 0 "$continued_commit"
    assert_commit_status "$commit_hook" 2 'FOO=1 git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'env GIT_X=1 git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'env -i -u HOME GIT_X=1 git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'command git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'builtin git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'exec git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'nohup git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'time git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'time -p git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 '/usr/bin/git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 '( git commit -m "bad" )'
    assert_commit_status "$commit_hook" 2 '{ git commit -m "bad"; }'
    assert_commit_status "$commit_hook" 2 'if git commit -m "bad"; then :; fi'
    assert_commit_status "$commit_hook" 2 '! git commit -m "bad"'
    assert_commit_status "$commit_hook" 2 'while git commit -m "bad"; do :; done'
    assert_commit_status "$commit_hook" 2 'until git commit -m "bad"; do :; done'
    assert_commit_status "$commit_hook" 0 'git commit -am "bad message"'
    assert_commit_status "$commit_hook" 0 'git commit -sm "bad"'
    assert_commit_status "$commit_hook" 0 'git commit -vam "bad"'
    assert_commit_status "$commit_hook" 0 'git commit -ambad'
    assert_commit_status "$commit_hook" 2 'git commit --mess "bad"'
    assert_commit_status "$commit_hook" 2 'git commit --messa=bad'
    assert_commit_status "$commit_hook" 0 'git commit -am "fix: ok"'
    assert_commit_status "$commit_hook" 0 'git commit "-amfix: ok"'
    assert_commit_status "$commit_hook" 0 'git commit -aF msg.txt'
    assert_commit_status "$commit_hook" 0 'git commit --fil msg.txt'
    assert_commit_status "$commit_hook" 0 'git commit --fil=msg.txt'

    # Certain message forms only: ambiguous syntax belongs to lefthook.
    assert_commit_status "$commit_hook" 2 'git commit -m "bad message" -SABCDEF12'
    assert_commit_status "$commit_hook" 0 'git commit -Cmain -m "fix: ok"'
    assert_commit_status "$commit_hook" 2 'git commit --m "bad message"'
    assert_commit_status "$commit_hook" 2 'git commit --me=bad'
    assert_commit_status "$commit_hook" 2 'curl http://x/#frag && git commit -m "bad message"'
    assert_commit_status "$commit_hook" 2 'git commit -m "feat: ok" && git commit -m "bad message"'
    assert_commit_status "$commit_hook" 2 'git --attr-source HEAD commit -m "bad message"'
    assert_commit_status "$commit_hook" 0 "git commit -m \$'feat: ok'"
    assert_commit_status "$commit_hook" 0 'git commit -m "$MESSAGE"'
    assert_commit_status "$commit_hook" 0 "printf x; $continued_commit"
    assert_commit_status "$commit_hook" 0 'git commit -m "bad message" && git commit -am "bad"'
    assert_commit_status "$commit_hook" 2 'git commit -C main -m "bad message"'
    assert_commit_status "$commit_hook" 0 "$unquoted_heredoc_header"
    assert_commit_status "$commit_hook" 0 'git commit -m "`echo feat`: ok"'
    assert_commit_status "$commit_hook" 0 "$quoted_heredoc_literals"
    assert_commit_status "$commit_hook" 0 'true # note ; git commit -m "bad message"'
    assert_commit_status "$commit_hook" 2 'git commit -u -m "bad message"'
    assert_commit_status "$commit_hook" 2 'true |& git commit -m "bad message"'
    assert_commit_status "$commit_hook" 0 'git commit --amend --no-edit;(echo -m "not a message")'
    assert_commit_status "$commit_hook" 0 '(git commit --no-edit)|grep -m1 x'
    assert_commit_status "$commit_hook" 2 'true;(git commit -m "bad message")'
    assert_commit_status "$commit_hook" 0 'echo "" git commit -m "bad message"'

done

echo "==> conventional commit extraction OK"

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

echo "==> agy adapter follows Cwd to the worktree root and exports CLAUDE_PROJECT_DIR"
agy_fixture="$tmpdir/agy-fixture"
mkdir -p "$agy_fixture/.agents" "$agy_fixture/.claude/hooks"
cp "$repo/.agents/agy-adapter.sh" "$agy_fixture/.agents/agy-adapter.sh"
cat >"$agy_fixture/.claude/hooks/probe.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'PWD=%s CPD=%s\n' "$PWD" "${CLAUDE_PROJECT_DIR:-unset}" >>"$AGY_PROBE_LOG"
EOF
chmod +x "$agy_fixture/.claude/hooks/probe.sh"
git -C "$agy_fixture" init -q >/dev/null
git -C "$agy_fixture" config user.email "test@example.com" >/dev/null
git -C "$agy_fixture" config user.name "Test" >/dev/null
git -C "$agy_fixture" config commit.gpgsign false >/dev/null
git -C "$agy_fixture" add -A >/dev/null
git -C "$agy_fixture" commit -q -m init >/dev/null
agy_wt="$tmpdir/agy-fixture-wt"
git -C "$agy_fixture" worktree add -q "$agy_wt" -b agy-wt-branch >/dev/null
mkdir -p "$agy_wt/some/subdir"
agy_expected_root="$(git -C "$agy_wt" rev-parse --show-toplevel)"

agy_probe_log="$tmpdir/agy-probe.log"
: >"$agy_probe_log"
payload_a="$(jq -n --arg cwd "$agy_wt/some/subdir" '{toolCall: {name: "run_command", args: {CommandLine: "ls", Cwd: $cwd}}}')"
result_a="$(cd "$tmpdir" && AGY_PROBE_LOG="$agy_probe_log" bash -c 'printf "%s" "$1" | bash "$2" ./.claude/hooks/probe.sh PreToolUse' _ "$payload_a" "$agy_fixture/.agents/agy-adapter.sh")"
[ "$result_a" = '{"decision": "allow"}' ] || fail "agy-adapter (worktree Cwd) did not allow: $result_a"
[ -f "$agy_probe_log" ] || fail "agy-adapter (worktree Cwd) never ran the probe hook"
probe_line="$(cat "$agy_probe_log")"
[ "$probe_line" = "PWD=$agy_expected_root CPD=$agy_expected_root" ] ||
    fail "agy-adapter (worktree Cwd) expected PWD/CPD=$agy_expected_root, got: $probe_line"

# The fixture asks only when the adapter delivered Antigravity's CommandLine as
# Claude's .tool_input.command, so a passing test proves the translation the
# registered block-no-verify and enforce-conventional-commits hooks rely on,
# not merely that an "ask" string survives the round trip.
cat >"$agy_fixture/.claude/hooks/ask.sh" <<'EOF'
#!/usr/bin/env bash
received="$(jq -r '.tool_input.command // empty')"
if [ "$received" = "ls --fixture-marker" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"fixture asks"}}'
fi
EOF
chmod +x "$agy_fixture/.claude/hooks/ask.sh"
payload_ask="$(jq -n --arg cwd "$agy_wt/some/subdir" '{toolCall: {name: "run_command", args: {CommandLine: "ls --fixture-marker", Cwd: $cwd}}}')"
result_ask="$(cd "$tmpdir" && bash -c 'printf "%s" "$1" | bash "$2" ./.claude/hooks/ask.sh PreToolUse' _ "$payload_ask" "$agy_fixture/.agents/agy-adapter.sh")"
printf '%s' "$result_ask" | jq -e '
    .decision == "ask" and (.reason | type == "string" and length > 0)
' >/dev/null || fail "agy-adapter did not preserve a hook's ask decision: $result_ask"

echo "==> agy adapter always executes ITS OWN hook, even when the target worktree's copy is tampered"
cat >"$agy_wt/.claude/hooks/probe.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'TAMPERED ran PWD=%s CPD=%s\n' "$PWD" "${CLAUDE_PROJECT_DIR:-unset}" >>"$AGY_PROBE_LOG"
EOF
git -C "$agy_wt" add -A >/dev/null
git -C "$agy_wt" commit -q -m "tamper: neuter the safety hook on this branch" >/dev/null
: >"$agy_probe_log"
result_tamper="$(cd "$tmpdir" && AGY_PROBE_LOG="$agy_probe_log" bash -c 'printf "%s" "$1" | bash "$2" ./.claude/hooks/probe.sh PreToolUse' _ "$payload_a" "$agy_fixture/.agents/agy-adapter.sh")"
[ "$result_tamper" = '{"decision": "allow"}' ] || fail "agy-adapter (tampered worktree hook) did not allow: $result_tamper"
probe_line_tamper="$(cat "$agy_probe_log")"
[ "$probe_line_tamper" = "PWD=$agy_expected_root CPD=$agy_expected_root" ] ||
    fail "agy-adapter ran the target worktree's own (tampered) hook instead of its trusted copy: $probe_line_tamper"

echo "==> agy adapter refuses a Cwd from a foreign checkout (no cd, foreign hook not run)"
agy_foreign="$tmpdir/agy-foreign"
mkdir -p "$agy_foreign/.claude/hooks"
cat >"$agy_foreign/.claude/hooks/probe.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'FOREIGN ran\n' >>"$AGY_FOREIGN_LOG"
EOF
chmod +x "$agy_foreign/.claude/hooks/probe.sh"
git -C "$agy_foreign" init -q >/dev/null
git -C "$agy_foreign" config user.email "test@example.com" >/dev/null
git -C "$agy_foreign" config user.name "Test" >/dev/null
git -C "$agy_foreign" config commit.gpgsign false >/dev/null
git -C "$agy_foreign" add -A >/dev/null
git -C "$agy_foreign" commit -q -m init >/dev/null

agy_neutral="$tmpdir/agy-neutral"
mkdir -p "$agy_neutral"
agy_foreign_log="$tmpdir/agy-foreign-ran.log"
payload_b="$(jq -n --arg cwd "$agy_foreign" '{toolCall: {name: "run_command", args: {CommandLine: "ls", Cwd: $cwd}}}')"
result_b="$(cd "$agy_neutral" && AGY_FOREIGN_LOG="$agy_foreign_log" bash -c 'printf "%s" "$1" | bash "$2" ./.claude/hooks/probe.sh PreToolUse' _ "$payload_b" "$agy_fixture/.agents/agy-adapter.sh")"
decision_b="$(printf '%s' "$result_b" | jq -r '.decision')"
[ "$decision_b" = "deny" ] || fail "agy-adapter followed a foreign Cwd instead of denying: $result_b"
[ -f "$agy_foreign_log" ] && fail "agy-adapter ran the foreign checkout's hook"

echo "==> agy adapter worktree-root Cwd resolution OK"

# ---------------------------------------------------------------------------
# protect-files: credential-shaped protection regression (#1019, #124)
# ---------------------------------------------------------------------------
# The hook keeps credential-shaped protections (.env, .pem, .key,
# .claude/settings.json, machine-level .codex/config.toml, /etc/claude-code/,
# /etc/codex/), Git control structures (refusing direct writes under .git/
# except for dev-flow-v2/ records and Git-derived deferred-findings sidecars),
# and Terraform state/internals, while dropping lockfiles, node_modules/, dist/,
# and binary/PDF suffixes.

hook_protect="private_dot_claude/hooks/executable_protect-files.sh"

protect_payload() {
    jq -n --arg file "$1" '{"tool_input":{"file_path":$file}}'
}

assert_protect_blocks() {
    local hook="$1" file="$2"
    local stderr_out
    local status=0
    stderr_out="$(protect_payload "$file" | bash "$repo/$hook" 2>&1 >/dev/null)" || status=$?
    if [ "$status" -ne 2 ]; then
        fail "$hook allowed '$file' (exit $status, expected 2)"
    fi
    if [[ "$stderr_out" != *"protect-files: blocked write to '$file'"* ]]; then
        fail "$hook blocked '$file' with unexpected stderr: $stderr_out"
    fi
}

assert_protect_allows() {
    local hook="$1" file="$2"
    local stderr_out
    local status=0
    stderr_out="$(protect_payload "$file" | bash "$repo/$hook" 2>&1 >/dev/null)" || status=$?
    if [ "$status" -ne 0 ]; then
        fail "$hook unexpectedly blocked '$file' (exit $status): $stderr_out"
    fi
}

if [ ! -f "$repo/$hook_protect" ]; then
    fail "$hook_protect absent"
elif [ ! -x "$repo/$hook_protect" ]; then
    fail "$hook_protect exists but is not executable"
else
    echo "==> protect-files blocks credential-shaped paths"
    assert_protect_blocks "$hook_protect" ".env"
    assert_protect_blocks "$hook_protect" "/repo/.env"
    assert_protect_blocks "$hook_protect" "/repo/.env.local"
    assert_protect_blocks "$hook_protect" "/repo/prod.env"
    assert_protect_blocks "$hook_protect" "/repo/subdir/.env.local"
    assert_protect_blocks "$hook_protect" "/repo/sub/.env.production"
    assert_protect_blocks "$hook_protect" "/repo/.envrc"
    assert_protect_blocks "$hook_protect" "secrets.pem"
    assert_protect_blocks "$hook_protect" "/repo/certs/server.pem"
    assert_protect_blocks "$hook_protect" "server.key"
    assert_protect_blocks "$hook_protect" "/repo/keys/id_rsa.key"
    assert_protect_blocks "$hook_protect" ".claude/settings.json"
    assert_protect_blocks "$hook_protect" "/repo/.claude/settings.json"
    assert_protect_blocks "$hook_protect" "/etc/claude-code/x"
    assert_protect_blocks "$hook_protect" "/etc/claude-code/config.json"
    assert_protect_blocks "$hook_protect" "/etc/codex/x"

    echo "==> protect-files blocks Terraform state and internals"
    assert_protect_blocks "$hook_protect" ".terraform/main.tf"
    assert_protect_blocks "$hook_protect" "/repo/.terraform/main.tf"
    assert_protect_blocks "$hook_protect" "terraform.tfstate"
    assert_protect_blocks "$hook_protect" "/repo/terraform.tfstate"
    assert_protect_blocks "$hook_protect" "/repo/terraform.tfstate.backup"
    assert_protect_blocks "$hook_protect" "/repo/infra/prod.tfstate"

    echo "==> protect-files blocks Git control internals"
    fixture_repo="$tmpdir/fixture-repo"
    mkdir -p "$fixture_repo"
    git -C "$fixture_repo" init -q
    mkdir -p "$fixture_repo/.git/dev-flow-v2/lanes/l" "$fixture_repo/.git/worktrees/w/deferred-findings"

    assert_protect_blocks "$hook_protect" ".git"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git"
    assert_protect_blocks "$hook_protect" ".git/config"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/config"
    assert_protect_blocks "$hook_protect" ".git/HEAD"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/HEAD"
    assert_protect_blocks "$hook_protect" ".git/index"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/index"
    assert_protect_blocks "$hook_protect" ".git/refs/heads/main"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/refs/heads/main"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/hooks/pre-commit"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.GIT/config"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.Git/hooks/pre-commit"
    assert_protect_blocks "$hook_protect" ".git/worktrees/wt/refs/worktree/deferred-findings"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/worktrees/wt/refs/worktree/deferred-findings"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/worktrees/wt/refs/heads/deferred-findings"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/worktrees/a/b/deferred-findings/sidecar.md"
    assert_protect_blocks "$hook_protect" ".git/worktrees/w/deferred-findings/sidecar.md"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/worktrees/w/deferred-findings/sidecar.md"
    echo "==> protect-files allows Git-derived normal-checkout sidecars"
    mkdir -p "$fixture_repo/.git/deferred-findings"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/deferred-findings/branch"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/deferred-findings/branch.md"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/deferred-findings/feat/x.md"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/../config"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings-evil/x"
    ln -s "$tmpdir/outside-sidecar.md" "$fixture_repo/.git/deferred-findings/escape"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/escape"

    echo "==> protect-files normalizes linked-worktree gitlink aliases"
    linked_fixture="$tmpdir/protect-linked-worktree"
    git -C "$fixture_repo" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m "test: initialize protect fixture"
    git -C "$fixture_repo" worktree add -q --detach "$linked_fixture" HEAD
    (
        export CLAUDE_PROJECT_DIR="$linked_fixture"
        mkdir -p "$linked_fixture/x"
        (
            cd "$linked_fixture"
            export CLAUDE_PROJECT_DIR=.
            touch protected-target.key
            ln -s protected-target.key neutral-alias.txt
            assert_protect_blocks "$hook_protect" "neutral-alias.txt"
            assert_protect_allows "$hook_protect" ".git/dev-flow-v2/runs/r/run.json"
        )
        for project_alias in "$linked_fixture/" "$linked_fixture/."; do
            CLAUDE_PROJECT_DIR="$project_alias" assert_protect_allows "$hook_protect" ".git/dev-flow-v2/runs/r/run.json"
            CLAUDE_PROJECT_DIR="$project_alias" assert_protect_blocks "$hook_protect" ".git/config"
        done
        assert_protect_allows "$hook_protect" ".git/dev-flow-v2/runs/r/run.json"
        assert_protect_allows "$hook_protect" "./.git/dev-flow-v2/runs/r/run.json"
        assert_protect_allows "$hook_protect" "x/../.git/dev-flow-v2/runs/r/run.json"
        assert_protect_blocks "$hook_protect" "./.git/config"
        assert_protect_blocks "$hook_protect" "./.git/hooks/pre-commit"
        ln -s "$fixture_repo/.git/config" "$fixture_repo/.git/dev-flow-v2/linked-escape"
        assert_protect_blocks "$hook_protect" "./.git/dev-flow-v2/linked-escape"
        mkdir -p "$fixture_repo/.git/hooks/child"
        ln -s "$fixture_repo/.git/hooks/child" "$linked_fixture/git-parent-link"
        assert_protect_blocks "$hook_protect" "./git-parent-link/../.git/dev-flow-v2/runs/r/run.json"
        ln -s "$fixture_repo/.git/hooks/child" "$fixture_repo/.git/dev-flow-v2/linked-parent"
        assert_protect_blocks "$hook_protect" "./.git/dev-flow-v2/linked-parent/../pre-commit"
    )

    echo "==> protect-files allows Git-derived linked-worktree sidecars"
    linked_gitdir="$(git -C "$linked_fixture" rev-parse --absolute-git-dir)"
    mkdir -p "$linked_gitdir/deferred-findings"
    assert_protect_allows "$hook_protect" "$linked_gitdir/deferred-findings/branch.md"
    assert_protect_allows "$hook_protect" "$linked_gitdir/deferred-findings/feat/x.md"
    # R9: a caller in another checkout may write this worktree's sidecars.
    CLAUDE_PROJECT_DIR="$fixture_repo" assert_protect_allows "$hook_protect" "$linked_gitdir/deferred-findings/other.md"
    assert_protect_blocks "$hook_protect" "$linked_gitdir/HEAD"
    assert_protect_blocks "$hook_protect" "$linked_gitdir/gitdir"
    assert_protect_blocks "$hook_protect" "$linked_gitdir/deferred-findings-evil/x"
    assert_protect_blocks "$hook_protect" "$linked_gitdir/deferred-findings/../HEAD"
    ln -s "$tmpdir/outside-linked-sidecar.md" "$linked_gitdir/deferred-findings/escape"
    assert_protect_blocks "$hook_protect" "$linked_gitdir/deferred-findings/escape"

    echo "==> protect-files allows sidecars through symlinked ancestors"
    ancestor_alias="$tmpdir/protect-ancestor-alias"
    ln -s "$tmpdir" "$ancestor_alias"
    assert_protect_allows "$hook_protect" "$ancestor_alias/fixture-repo/.git/deferred-findings/feat/x.md"
    physical_tmpdir="$(cd -P -- "$tmpdir" && pwd -P)"
    linked_gitdir_alias="$ancestor_alias${linked_gitdir#"$physical_tmpdir"}"
    assert_protect_allows "$hook_protect" "$linked_gitdir_alias/deferred-findings/feat/x.md"

    echo "==> protect-files refuses aliased exception roots (challenge r1)"
    for alias_target in . ..; do
        alias_repo="$tmpdir/root-alias-${#alias_target}"
        git init -q "$alias_repo"
        ln -s "$alias_target" "$alias_repo/.git/deferred-findings"
        # R11: canonicalizing the nearest directory must not hide this root alias.
        assert_protect_blocks "$hook_protect" "$alias_repo/.git/deferred-findings/x"
        for internal in config HEAD hooks/pre-commit; do
            assert_protect_blocks "$hook_protect" "$alias_repo/.git/$internal"
            assert_protect_blocks "$hook_protect" "$alias_repo/.git/deferred-findings/$internal"
        done
        # An invalid sidecar root does not revoke the other, valid exception.
        assert_protect_allows "$hook_protect" "$alias_repo/.git/dev-flow-v2/run.json"
    done
    alias_repo="$tmpdir/dev-flow-root-alias"
    git init -q "$alias_repo"
    ln -s hooks "$alias_repo/.git/dev-flow-v2"
    assert_protect_blocks "$hook_protect" "$alias_repo/.git/hooks/pre-commit"
    assert_protect_blocks "$hook_protect" "$alias_repo/.git/dev-flow-v2/pre-commit"
    assert_protect_allows "$hook_protect" "$alias_repo/.git/deferred-findings/branch.md"

    alias_worktree="$tmpdir/sidecar-root-alias-worktree"
    git -C "$fixture_repo" worktree add -q --detach "$alias_worktree" HEAD
    alias_gitdir="$(git -C "$alias_worktree" rev-parse --absolute-git-dir)"
    ln -s .. "$alias_gitdir/deferred-findings"
    assert_protect_blocks "$hook_protect" "$alias_gitdir/HEAD"
    assert_protect_blocks "$hook_protect" "$alias_gitdir/deferred-findings/protect-linked-worktree/HEAD"

    echo "==> protect-files refuses control characters before path comparison"
    newline_repo="$tmpdir/"$'newline\nancestor'
    git init -q "$newline_repo"
    assert_protect_blocks "$hook_protect" "$newline_repo/.git/config"
    assert_protect_blocks "$hook_protect" "$newline_repo/.git/deferred-findings/branch.md"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/"$'tab\tbranch.md'
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/"$'return\rbranch.md'
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/"$'trailing\n'
    ln -s "$fixture_repo/.git/deferred-findings/"$'trailing\n' "$fixture_repo/neutral-control-alias"
    assert_protect_blocks "$hook_protect" "$fixture_repo/neutral-control-alias"

    echo "==> protect-files fails closed when sidecar root computation fails"
    fake_git_bin="$tmpdir/protect-failing-git"
    mkdir -p "$fake_git_bin"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_git_bin/git"
    chmod +x "$fake_git_bin/git"
    PATH="$fake_git_bin:$PATH" assert_protect_blocks "$hook_protect" "$linked_gitdir/deferred-findings/branch.md"
    # Also fail closed when common-dir lookup succeeds but sidecar lookup fails.
    real_git="$(command -v git)"
    cat >"$fake_git_bin/git" <<'SCRIPT'
#!/usr/bin/env bash
for arg in "$@"; do
    [[ "$arg" != "--git-path" ]] || exit 1
done
exec "$PROTECT_TEST_REAL_GIT" "$@"
SCRIPT
    PROTECT_TEST_REAL_GIT="$real_git" PATH="$fake_git_bin:$PATH" assert_protect_blocks "$hook_protect" "$linked_gitdir/deferred-findings/branch.md"

    echo "==> protect-files blocks credential and managed config through symlinks"
    secret_target="$tmpdir/secret.key"
    touch "$secret_target"
    symlink_secret="$tmpdir/not-a-secret-name.txt"
    ln -s "$secret_target" "$symlink_secret"
    assert_protect_blocks "$hook_protect" "$symlink_secret"

    env_target="$tmpdir/.env"
    touch "$env_target"
    symlink_env="$tmpdir/regular-file.conf"
    ln -s "$env_target" "$symlink_env"
    assert_protect_blocks "$hook_protect" "$symlink_env"

    claude_target="$tmpdir/.claude/settings.json"
    mkdir -p "$tmpdir/.claude"
    touch "$claude_target"
    symlink_claude="$tmpdir/my-custom-settings.json"
    ln -s "$claude_target" "$symlink_claude"
    assert_protect_blocks "$hook_protect" "$symlink_claude"

    echo "==> protect-files blocks symlinks escaping dev-flow directories"
    touch "$tmpdir/outside-target.txt"
    ln -s "$tmpdir/outside-target.txt" "$fixture_repo/.git/dev-flow-v2/escape-outside"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/dev-flow-v2/escape-outside"

    touch "$fixture_repo/.git/config"
    ln -s "$fixture_repo/.git/config" "$fixture_repo/.git/dev-flow-v2/escape-to-git-config"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/dev-flow-v2/escape-to-git-config"

    echo "==> protect-files blocks symlink-plus-parent traversal escaping dev-flow directory"
    mkdir -p "$tmpdir/symlink-parent-out/child"
    touch "$tmpdir/symlink-parent-out/victim"
    ln -s "$tmpdir/symlink-parent-out/child" "$fixture_repo/.git/dev-flow-v2/link"
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/dev-flow-v2/link/../victim"

    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/dev-flow-v2/../config"

    echo "==> protect-files blocks paths outside any repository"
    outside_repo="$tmpdir/outside-non-repo"
    mkdir -p "$outside_repo/.git/dev-flow-v2/lanes/l"
    assert_protect_blocks "$hook_protect" "$outside_repo/.git/dev-flow-v2/lanes/l/report.md"
    assert_protect_blocks "$hook_protect" "$outside_repo/.git/config"
    assert_protect_blocks "$hook_protect" "$outside_repo/.git/deferred-findings/feat/x.md"

    echo "==> protect-files allows dev-flow records and dropped patterns"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/dev-flow-v2/lanes/l/report-1.md"
    assert_protect_allows "$hook_protect" ".git/dev-flow-v2/lanes/l/report-1.md"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/dev-flow-v2/runs/r/run.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/.git/dev-flow-v2/lanes/../runs/r/run.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/package-lock.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/uv.lock"
    assert_protect_allows "$hook_protect" "$fixture_repo/node_modules/foo/index.js"
    assert_protect_allows "$hook_protect" "$fixture_repo/dist/x.js"
    assert_protect_allows "$hook_protect" "$fixture_repo/img.png"
    assert_protect_allows "$hook_protect" "$fixture_repo/photo.jpg"
    assert_protect_allows "$hook_protect" "$fixture_repo/doc.pdf"
    assert_protect_allows "$hook_protect" "$fixture_repo/ai/schemas/result.envelope.schema.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/config.environment.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/config.env.js"
    assert_protect_allows "$hook_protect" "$fixture_repo/src/env.ts"
    assert_protect_allows "$hook_protect" "$fixture_repo/env.config.json"
    assert_protect_allows "$hook_protect" "$fixture_repo/prod.env.local"
    assert_protect_allows "$hook_protect" "$fixture_repo/.env.d/README.md"
    assert_protect_allows "$hook_protect" "$fixture_repo/.environment/schema.json"
    assert_protect_allows "$hook_protect" ""

    echo "==> protect-files regression tests OK"
fi

# git-merge-guard replaces the Bash(git merge:*) ask rules; see the script header.
bash "$(dirname "${BASH_SOURCE[0]}")/test-git-merge-guard.sh"

# The project settings are now the only project-level merge backstop: the ask
# rules are gone, so the registration itself must be pinned. Both halves are
# checked so they cannot drift back into contradicting each other, and the
# registered command is run as written (asking on main, silent on a feature
# branch, asking when the guard cannot be found).
echo "==> .claude/settings.json registers git-merge-guard and drops the git merge ask rules"
project_settings="$repo/.claude/settings.json"
# `.matcher` is a regex Claude Code searches; "Bash" is what this repo writes,
# so it is matched exactly on purpose (a widened matcher fails loudly here).
registered="$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.type == "command" and (.command | contains("git-merge-guard.py")))
    | .command] | first // empty' "$project_settings")"
[ -n "$registered" ] || fail "no PreToolUse Bash hook in .claude/settings.json runs git-merge-guard.py"
case "$registered" in
*'"$CLAUDE_PROJECT_DIR/'*) ;;
*) fail "the registered git-merge-guard command must double-quote \$CLAUDE_PROJECT_DIR" ;;
esac
if jq -e '.permissions.ask[]? | select(. == "Bash(git merge)" or . == "Bash(git merge:*)")' "$project_settings" >/dev/null; then
    fail ".claude/settings.json still carries a Bash(git merge) ask rule beside the guard"
fi
guard_fixture="$tmpdir/guard-fixture"
git init -q -b main "$guard_fixture"
git -C "$guard_fixture" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'chore: fixture'
git -C "$guard_fixture" branch feat
git -C "$guard_fixture" remote add origin "$tmpdir/absent.git"
git -C "$guard_fixture" update-ref refs/remotes/origin/main HEAD
git -C "$guard_fixture" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$guard_fixture" worktree add -q "$guard_fixture/wt" feat
registered_decision() { # project-dir cwd command -> silent|ask|other|rc<N>
    local out rc
    out="$(jq -nc --arg c "$3" --arg d "$2" \
        '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
        CLAUDE_PROJECT_DIR="$1" bash -c "$registered" 2>"$tmpdir/registered.err")" && rc=0 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "rc${rc}: $(tr '\n' ' ' <"$tmpdir/registered.err")"
    elif [ -z "$out" ]; then
        echo silent
    elif jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$out" >/dev/null 2>&1; then
        echo ask
    else
        echo other
    fi
}
expect_registered() { # expected project-dir cwd command
    local got
    got="$(registered_decision "$2" "$3" "$4")"
    [ "$got" = "$1" ] || fail "registered git-merge-guard: expected=$1 got=$got :: $4 (project dir $2)"
}
expect_registered ask "$repo" "$guard_fixture" "git merge feat"
expect_registered silent "$repo" "$guard_fixture/wt" "git merge origin/main --no-edit"
expect_registered ask "$tmpdir/no-such-project" "$guard_fixture/wt" "git merge origin/main --no-edit"
# The quoting of $CLAUDE_PROJECT_DIR is exercised, not only pattern-matched: an
# unquoted path with a space would split, fail, and fall back to a permanent
# ask, which looks like the guard working while the silent case never happens.
ln -s "$repo" "$tmpdir/spaced project dir"
expect_registered ask "$tmpdir/spaced project dir" "$guard_fixture" "git merge feat"
expect_registered silent "$tmpdir/spaced project dir" "$guard_fixture/wt" "git merge origin/main --no-edit"
echo "==> git-merge-guard registration OK"

echo "==> user-level merge guard defers only when a project guard is present"
user_settings="$repo/.chezmoitemplates/claude-settings/enforced.json"
user_guard_count="$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.type == "command" and (.command | contains("~/.claude/hooks/git-merge-guard.py")))] | length' \
    "$user_settings")"
[ "$user_guard_count" = 1 ] || fail "expected exactly one user-level merge guard registration, got $user_guard_count"
user_registered="$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.type == "command" and (.command | contains("~/.claude/hooks/git-merge-guard.py")))
    | .command] | first // empty' "$user_settings")"
[ -n "$user_registered" ] || fail "the user-level merge guard registration is missing"

registered_project="$tmpdir/registered project"
registered_home="$tmpdir/user home"
no_project_guard="$tmpdir/no-project-guard"
mkdir -p "$registered_project/.claude/hooks" "$registered_home/.claude/hooks" "$no_project_guard"
guard_calls="$tmpdir/guard-calls"
: >"$guard_calls"
cat >"$registered_home/.claude/hooks/git-merge-guard.py" <<'PY'
import os

with open(os.environ["MERGE_GUARD_CALLS"], "a", encoding="utf-8") as calls:
    calls.write("user\n")
PY
cat >"$registered_project/.claude/hooks/git-merge-guard.py" <<'PY'
import os

with open(os.environ["MERGE_GUARD_CALLS"], "a", encoding="utf-8") as calls:
    calls.write("project\n")
PY
registered_project_fallback="|| printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"git-merge-guard failed to run\"}}'"
registered_project_command="python3 \"\$CLAUDE_PROJECT_DIR/.claude/hooks/git-merge-guard.py\" $registered_project_fallback"
jq -n --arg command "$registered_project_command" \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' \
    >"$registered_project/.claude/settings.json"
project_registered="$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.type == "command" and (.command | contains("/.claude/hooks/git-merge-guard.py")))
    | .command] | first // empty' "$registered_project/.claude/settings.json")"
[ -n "$project_registered" ] || fail "the project fixture did not register its local merge guard"

invoke_registered_guard() { # registration project-dir home-dir calls-file
    local registration="$1" project_dir="$2" home_dir="$3" calls_file="$4"
    printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"git merge feature"},"cwd":"/tmp"}' |
        HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" MERGE_GUARD_CALLS="$calls_file" \
            bash -c "$registration" 2>"$tmpdir/registered-hook.err"
}

# Both registrations are invoked for one simulated Bash call. The user-level
# copy is a no-op; the project registration alone reaches its guard.
user_output="$(invoke_registered_guard "$user_registered" "$registered_project" "$registered_home" "$guard_calls")" ||
    fail "the user-level registration failed with a registered project guard"
project_output="$(invoke_registered_guard "$project_registered" "$registered_project" "$registered_home" "$guard_calls")" ||
    fail "the project-level registration failed"
[ -z "$user_output" ] && [ -z "$project_output" ] ||
    fail "successful guard registrations unexpectedly emitted a permission decision"
[ "$(cat "$guard_calls")" = project ] ||
    fail "expected only the registered project guard to decide, got: $(tr '\n' ' ' <"$guard_calls")"

# The dotfiles project's source-path registration is also an exact, fail-closed
# project guard and should suppress the user-level copy.
source_registered_project="$tmpdir/source-path registered project"
mkdir -p "$source_registered_project/.claude" "$source_registered_project/private_dot_claude/hooks"
cp "$registered_project/.claude/hooks/git-merge-guard.py" \
    "$source_registered_project/private_dot_claude/hooks/executable_git-merge-guard.py"
source_project_command="python3 \"\$CLAUDE_PROJECT_DIR/private_dot_claude/hooks/executable_git-merge-guard.py\" $registered_project_fallback"
jq -n --arg command "$source_project_command" \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' \
    >"$source_registered_project/.claude/settings.json"
: >"$guard_calls"
user_output="$(invoke_registered_guard "$user_registered" "$source_registered_project" "$registered_home" "$guard_calls")" ||
    fail "the user-level registration failed with the exact source-path project guard"
project_output="$(invoke_registered_guard "$source_project_command" "$source_registered_project" "$registered_home" "$guard_calls")" ||
    fail "the exact source-path project registration failed"
[ -z "$user_output" ] && [ -z "$project_output" ] && [ "$(cat "$guard_calls")" = project ] ||
    fail "the exact source-path registration did not leave the project guard as the sole decider"

# File presence without an active PreToolUse Bash registration must not
# suppress the user-level guard. Check absent settings, the wrong matcher, and
# a Bash registration for a different hook.
unregistered_project="$tmpdir/present but unregistered project"
mkdir -p "$unregistered_project/.claude/hooks"
cp "$registered_project/.claude/hooks/git-merge-guard.py" \
    "$unregistered_project/.claude/hooks/git-merge-guard.py"
assert_user_guard_runs() { # project-dir reason
    local project_dir="$1" reason="$2" output
    : >"$guard_calls"
    output="$(invoke_registered_guard "$user_registered" "$project_dir" "$registered_home" "$guard_calls")" ||
        fail "the user-level registration failed for $reason"
    [ -z "$output" ] && [ "$(cat "$guard_calls")" = user ] ||
        fail "the user guard did not run for $reason (calls: $(tr '\n' ' ' <"$guard_calls"))"
}
assert_user_guard_runs "$unregistered_project" "an absent project settings file"
jq -n --arg command "$registered_project_command" \
    '{hooks:{PreToolUse:[{matcher:"Edit",hooks:[{type:"command",command:$command}]}]}}' \
    >"$unregistered_project/.claude/settings.json"
assert_user_guard_runs "$unregistered_project" "a guard command registered for Edit, not Bash"
jq -n --arg command 'python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/other-hook.py"' \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' \
    >"$unregistered_project/.claude/settings.json"
assert_user_guard_runs "$unregistered_project" "a Bash registration for a different hook"
jq -n --arg command ': # git-merge-guard.py disabled' \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' \
    >"$unregistered_project/.claude/settings.json"
assert_user_guard_runs "$unregistered_project" "a commented-out guard command"
jq -n --arg command 'python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/git-merge-guard.py" || true' \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' \
    >"$unregistered_project/.claude/settings.json"
assert_user_guard_runs "$unregistered_project" "a fail-open guard command"

# Without a project guard file, the user-level hook still runs.
: >"$guard_calls"
user_output="$(invoke_registered_guard "$user_registered" "$no_project_guard" "$registered_home" "$guard_calls")" ||
    fail "the user-level registration failed without a project guard"
[ -z "$user_output" ] && [ "$(cat "$guard_calls")" = user ] ||
    fail "the user guard did not run by itself when no project guard exists"

# A missing deployed user hook still fails closed with the original ask result.
missing_user_home="$tmpdir/missing user hook home"
mkdir -p "$missing_user_home/.claude/hooks"
fallback_output="$(invoke_registered_guard "$user_registered" "$no_project_guard" "$missing_user_home" "$guard_calls")" ||
    fail "the fail-closed user-hook fallback returned non-zero"
jq -e '.hookSpecificOutput.permissionDecision == "ask" and
    .hookSpecificOutput.permissionDecisionReason == "git-merge-guard failed to run"' \
    <<<"$fallback_output" >/dev/null ||
    fail "a missing user-level merge guard did not preserve its fail-closed ask fallback"
echo "==> single merge-guard execution and fallback OK"

echo "==> user-level and project-level merge guard copies remain byte-identical"
user_guard_source="$repo/private_dot_claude/hooks/executable_git-merge-guard.py"
project_guard_source="$repo/.claude/hooks/git-merge-guard.py"
guard_copy_check() { cmp -s "$1" "$2"; }
guard_copy_check "$user_guard_source" "$project_guard_source" ||
    fail "the chezmoi user-level merge guard differs from the project copy"
divergent_guard="$tmpdir/divergent-git-merge-guard.py"
cp "$project_guard_source" "$divergent_guard"
printf '\n# simulated divergence\n' >>"$divergent_guard"
if guard_copy_check "$user_guard_source" "$divergent_guard"; then
    fail "the merge-guard byte-identity check accepted a simulated divergence"
fi
echo "==> git-merge-guard copy identity and divergence check OK"
