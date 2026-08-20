#!/usr/bin/env bash
# Validate personal AI harness configuration without touching $HOME.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
profile="$repo/private_dot_codex/private_harmon-local.config.toml"
opencode_dir="$repo/dot_config/opencode"
opencode_config="$opencode_dir/opencode.jsonc"
opencode_tui="$opencode_dir/tui.jsonc"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/home" "$test_tmp/config" "$test_tmp/data" \
    "$test_tmp/cache" "$test_tmp/state" "$test_tmp/config/opencode"
cp "$opencode_config" "$opencode_tui" "$test_tmp/config/opencode/"

opencode_test() {
    HOME="$test_tmp/home" \
        XDG_CONFIG_HOME="$test_tmp/config" \
        XDG_DATA_HOME="$test_tmp/data" \
        XDG_CACHE_HOME="$test_tmp/cache" \
        XDG_STATE_HOME="$test_tmp/state" \
        command opencode "$@"
}

echo "==> parse AI harness configuration"
jq -e . "$repo/private_dot_claude/private_settings.json" >/dev/null ||
    fail "Claude settings are not valid JSON"
jq -e . "$repo/private_dot_codex/private_hooks.json" >/dev/null ||
    fail "Codex hooks are not valid JSON"
jq -e . "$repo/private_dot_gemini/config/hooks.json" >/dev/null ||
    fail "Gemini hooks are not valid JSON"
sed 's/{{\s*\.chezmoi\.homeDir\s*}}/\/Users\/test/g' "$repo/private_dot_gemini/antigravity-cli/settings.json.tmpl" |
    jq -e . >/dev/null || fail "Antigravity CLI settings template is not valid JSON"
[ "$(sed 's/{{\s*\.chezmoi\.homeDir\s*}}/\/Users\/test/g' "$repo/private_dot_gemini/antigravity-cli/settings.json.tmpl" | jq -r '.statusLine.type')" = "command" ] ||
    fail "Antigravity CLI settings must configure command statusLine"
# Keep managed JSONC in the strict JSON subset for portable local validation.
jq -e . "$opencode_config" >/dev/null || fail "OpenCode config is not strict JSON"
jq -e . "$opencode_tui" >/dev/null || fail "OpenCode TUI config is not strict JSON"

for toml in \
    "$profile" \
    "$repo/private_dot_codex/agents/private_implementer.toml" \
    "$repo/private_dot_codex/agents/private_reviewer.toml"; do
    # Force YAML output so yq versions without a TOML encoder can still parse
    # and validate TOML input consistently on macOS and GitHub Actions.
    yq -oy '.' "$toml" >/dev/null || fail "invalid TOML: $toml"
done

[ "$(yq '.model' "$profile")" = "gpt-5.6-sol" ] ||
    fail "local Codex profile must use gpt-5.6-sol"
[ "$(yq '.model_reasoning_effort' "$profile")" = "medium" ] ||
    fail "local Codex profile must use medium reasoning"
[ "$(yq '.sandbox_mode' "$profile")" = "workspace-write" ] ||
    fail "local Codex profile must enable the workspace sandbox"
[ "$(yq '.approval_policy' "$profile")" = "on-request" ] ||
    fail "local Codex profile must use on-request approvals"
[ "$(yq '.project_doc_max_bytes' "$profile")" = "65536" ] ||
    fail "local Codex profile must load up to 64 KiB of project guidance"
[ "$(jq -r '.model' "$repo/private_dot_claude/private_settings.json")" = "claude-opus-4-8" ] ||
    fail "Claude must default to Opus 4.8"
[ "$(jq -r '.share' "$opencode_config")" = "disabled" ] ||
    fail "OpenCode personal default must disable session sharing"
[ "$(jq -r 'if .snapshot == true then "true" else "false" end' "$opencode_config")" = "true" ] ||
    fail "OpenCode personal default must enable snapshots"
[ "$(jq -r 'if (.subagent_depth | type) == "number" then .subagent_depth else -1 end' "$opencode_config")" = "1" ] ||
    fail "OpenCode personal default must limit subagent depth"
[ "$(jq -r '.model // ""' "$opencode_config")" = "" ] ||
    fail "OpenCode must remain provider and model neutral"
[ "$(jq -r '.attention.enabled | type' "$opencode_tui")" = "boolean" ] &&
    [ "$(jq -r '.attention.notifications | type' "$opencode_tui")" = "boolean" ] &&
    [ "$(jq -r '.attention.sound | type' "$opencode_tui")" = "boolean" ] &&
    [ "$(jq -r '.attention.enabled' "$opencode_tui")" = "true" ] &&
    [ "$(jq -r '.attention.notifications' "$opencode_tui")" = "true" ] &&
    [ "$(jq -r '.attention.sound' "$opencode_tui")" = "true" ] ||
    fail "OpenCode attention notifications and sounds must be enabled"
[ "$(yq '.sandbox_mode' "$repo/private_dot_codex/agents/private_reviewer.toml")" = "read-only" ] ||
    fail "Codex reviewer must be mechanically read-only"
if grep -Eq 'session-start-context|post-edit-format|enforce-conventional-commits' \
    "$repo/private_dot_codex/private_hooks.json"; then
    fail "user-trusted Codex hooks must not execute checkout-controlled tasks"
fi

echo "==> validate instruction and skill compatibility links"
[ -f "$repo/private_dot_agents/private_AGENTS.md" ] ||
    fail "standards-first global AGENTS.md source is missing"
[ "$(cat "$repo/private_dot_codex/symlink_AGENTS.md")" = "../.agents/AGENTS.md" ] ||
    fail "Codex AGENTS.md link does not target the shared global guidance"
[ "$(cat "$repo/private_dot_claude/symlink_CLAUDE.md")" = "../.agents/AGENTS.md" ] ||
    fail "Claude CLAUDE.md link does not target the shared global guidance"
[ "$(cat "$opencode_dir/symlink_AGENTS.md")" = "../../.agents/AGENTS.md" ] ||
    fail "OpenCode AGENTS.md link does not target the shared global guidance"
# Repository skills follow the same direction as the deployed ones below:
# .claude/skills is the real home the sync vendors into, and .agents/skills
# holds per-skill compatibility links that scripts/link-agent-skills.sh owns.
# (This used to be one directory symlink pointing the other way; harmon-init
# v4.27.0 ships link-agent-skills.sh, which requires this direction, and it is
# now what `task sync:skills` and `task verify` run.)
[ -d "$repo/.claude/skills" ] && [ ! -L "$repo/.claude/skills" ] ||
    fail "repository Claude skills path is not a real directory"
for skill in "$repo"/.claude/skills/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "${skill%/}")"
    [ -L "$repo/.agents/skills/$name" ] ||
        fail "missing portable compatibility link for skill: $name"
    [ "$(readlink "$repo/.agents/skills/$name")" = "../../.claude/skills/$name" ] ||
        fail "portable compatibility link for $name targets the wrong path"
done
[ "$(cat "$repo/private_dot_agents/skills/symlink_open-pr")" = "../../.claude/skills/open-pr" ] ||
    fail "open-pr compatibility link is wrong"
[ "$(cat "$repo/private_dot_agents/skills/symlink_rebase")" = "../../.claude/skills/rebase" ] ||
    fail "rebase compatibility link is wrong"
[ "$(cat "$repo/private_dot_agents/skills/symlink_standardize-repo")" = "../../.claude/skills/standardize-repo" ] ||
    fail "harmon-devkit standardize-repo compatibility link is wrong"
if command -v opencode >/dev/null 2>&1; then
    resolved_config="$(
        opencode_test debug config
    )" || fail "OpenCode rejected its managed configuration"
    [ "$(printf '%s' "$resolved_config" | jq -r '.share')" = "disabled" ] ||
        fail "OpenCode did not resolve sharing as disabled"
    [ "$(printf '%s' "$resolved_config" | jq -r '.snapshot')" = "true" ] ||
        fail "OpenCode did not resolve snapshots as enabled"
    [ "$(printf '%s' "$resolved_config" | jq -r '.subagent_depth')" = "1" ] ||
        fail "OpenCode did not resolve the managed subagent depth"

    plan_config="$(
        opencode_test debug agent plan
    )" || fail "OpenCode rejected its built-in plan agent"
    [ "$(printf '%s' "$plan_config" | jq -r '[.permission[] | select(.permission == "edit" and .pattern == "*")][-1].action')" = "deny" ] ||
        fail "global OpenCode permissions made the plan agent writable"
    [ "$(printf '%s' "$plan_config" | jq -r '[.permission[] | select(.permission == "bash" and .pattern == "*")][-1].action')" = "ask" ] ||
        fail "OpenCode plan shell does not require approval"

    build_config="$(
        opencode_test debug agent build
    )" || fail "OpenCode rejected its built-in build agent override"
    [ "$(printf '%s' "$build_config" | jq -r '[.permission[] | select(.permission == "bash" and .pattern == "*")][-1].action')" = "ask" ] ||
        fail "OpenCode build shell does not require approval by default"

    general_config="$(
        opencode_test debug agent general
    )" || fail "OpenCode rejected its built-in general subagent override"
    [ "$(printf '%s' "$general_config" | jq -r '[.permission[] | select(.permission == "bash" and .pattern == "*")][-1].action')" = "ask" ] ||
        fail "OpenCode general subagent shell does not require approval"

else
    echo "SKIP: opencode is unavailable; native config loading is covered on configured hosts"
fi

echo "==> validate Codex profile wrapper"
aliases_file="$repo/private_dot_dotfiles/private_dot_aliases"
stub_dir="$test_tmp/bin"
mkdir -p "$stub_dir"
printf '#!/bin/sh\nprintf "<%%s>\\n" "$@"\n' >"$stub_dir/codex"
chmod +x "$stub_dir/codex"

runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex exec test' _ "$aliases_file")"
[ "$runtime_args" = $'<--profile>\n<harmon-local>\n<exec>\n<test>' ] ||
    fail "Codex runtime command did not receive the local profile"
explicit_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex -ptest exec test' _ "$aliases_file")"
[ "$explicit_args" = $'<-ptest>\n<exec>\n<test>' ] ||
    fail "Codex wrapper did not preserve an attached explicit profile"
runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex debug prompt-input -- -ptest' _ "$aliases_file")"
[ "$runtime_args" = $'<--profile>\n<harmon-local>\n<debug>\n<prompt-input>\n<-->\n<-ptest>' ] ||
    fail "Codex wrapper treated option-delimited prompt text as a profile"
runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex debug -c foo=bar prompt-input' _ "$aliases_file")"
[ "$runtime_args" = $'<--profile>\n<harmon-local>\n<debug>\n<-c>\n<foo=bar>\n<prompt-input>' ] ||
    fail "Codex wrapper misclassified a valued debug option"
runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex -- doctor' _ "$aliases_file")"
[ "$runtime_args" = $'<--profile>\n<harmon-local>\n<-->\n<doctor>' ] ||
    fail "Codex wrapper treated option-delimited prompt text as a subcommand"
runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex -i first.png doctor -- "inspect these"' _ "$aliases_file")"
[ "$runtime_args" = $'<--profile>\n<harmon-local>\n<-i>\n<first.png>\n<doctor>\n<-->\n<inspect these>' ] ||
    fail "Codex wrapper treated a later variadic image value as a subcommand"
admin_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex --image=first.png doctor' _ "$aliases_file")"
[ "$admin_args" = $'<--image=first.png>\n<doctor>' ] ||
    fail "Codex wrapper treated an attached image value as variadic"
for subcommand in login doctor completion plugin features; do
    admin_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex "$2"' _ "$aliases_file" "$subcommand")"
    [ "$admin_args" = "<$subcommand>" ] ||
        fail "Codex wrapper profiled administrative subcommand: $subcommand"
done

for prefix in '--enable hooks' '-c key=value' '--disable hooks'; do
    admin_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex ${(z)2} doctor' _ "$aliases_file" "$prefix")"
    case "$admin_args" in
    *'<--profile>'*) fail "Codex wrapper profiled an option-prefixed administrative command: $prefix" ;;
    esac
done
admin_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex a task-id' _ "$aliases_file")"
[ "$admin_args" = $'<a>\n<task-id>' ] ||
    fail "Codex wrapper profiled the apply alias"
admin_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex --add-dir /tmp/a /tmp/b doctor' _ "$aliases_file")"
case "$admin_args" in
*'<--profile>'*) fail "Codex wrapper profiled an administrative command after multiple --add-dir values" ;;
esac
for runtime in 'sandbox echo ok' 'debug prompt-input'; do
    runtime_args="$(PATH="$stub_dir:$PATH" zsh -c 'source "$1"; codex ${(z)2}' _ "$aliases_file" "$runtime")"
    case "$runtime_args" in
    $'<--profile>\n<harmon-local>\n'*) ;;
    *) fail "Codex wrapper did not profile supported runtime command: $runtime" ;;
    esac
done

echo "==> validate Codex policy rules when the CLI is available"
if command -v codex >/dev/null 2>&1; then
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- git push origin main | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "git push should require approval, got $decision"
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- git -C /tmp/project merge main | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "option-prefixed git merge should require approval, got $decision"
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- git -C/tmp/project merge main | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "attached short-option git merge should require approval, got $decision"
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- git --git-dir=/tmp/project/.git push origin main | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "attached long-option git push should require approval, got $decision"
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- gh --repo=owner/repo pr merge 123 | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "attached-option gh pr merge should require approval, got $decision"
else
    echo "SKIP: codex is unavailable; execpolicy parsing is covered on configured hosts"
fi
echo "==> validate statusline renderers"
agy_sl="$repo/private_dot_gemini/antigravity-cli/executable_statusline.sh"
claude_sl="$repo/private_dot_claude/executable_statusline.sh"

[ -x "$agy_sl" ] || fail "Antigravity statusline script is missing or not executable"
[ -x "$claude_sl" ] || fail "Claude statusline script is missing or not executable"

# 1. Standard payload renders percentage and headroom
out=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'{"workspace":{"current_dir":"/"},"context_window":{"used_percentage":24,"context_window_size":1000000},"model":{"display_name":"Gemini 3.1 Pro (High)"},"conversation_id":"34ee01b6-2f37-4fe7"}')
case "$out" in *' 24%'*) ;; *) fail "Antigravity statusline expected 24%, got: $out" ;; esac
case "$out" in *'760k left'*) ;; *) fail "Antigravity statusline expected '760k left', got: $out" ;; esac
case "$out" in *'Gemini 3.1 Pro (High)'*) ;; *) fail "Antigravity statusline expected model name, got: $out" ;; esac
case "$out" in *'34ee01b6'*) ;; *) fail "Antigravity statusline expected session id, got: $out" ;; esac

# 2. Absent context renders 'context n/a' and never a false 0% gauge
out_absent=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'{"workspace":{"current_dir":"/"},"model":{"display_name":"Gemini 3.1 Pro"}}')
case "$out_absent" in *'context n/a'*) ;; *) fail "Antigravity statusline expected 'context n/a' for absent context, got: $out_absent" ;; esac
case "$out_absent" in *'0%'*) fail "Antigravity statusline rendered false 0% for absent context: $out_absent" ;; esac

# 3. Empty payload degrades gracefully
out_empty=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'')
[ -n "$out_empty" ] || fail "Antigravity statusline returned empty output on empty payload"

echo "==> AI harness configuration OK"
