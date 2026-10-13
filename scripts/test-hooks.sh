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
    "$repo/.devcontainer/config/claude-hooks/enforce-conventional-commits.sh"; do
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
# except for dev-flow-v2/ records), and Terraform state/internals, while
# dropping lockfiles, node_modules/, dist/, and binary/PDF suffixes.

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
    assert_protect_blocks "$hook_protect" "$fixture_repo/.git/deferred-findings/branch"

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
