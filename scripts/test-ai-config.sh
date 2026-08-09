#!/usr/bin/env bash
# Validate the paired Claude/Codex configuration without touching $HOME.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
profile="$repo/private_dot_codex/private_harmon-local.config.toml"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

echo "==> parse Claude and Codex configuration"
jq -e . "$repo/private_dot_claude/private_settings.json" >/dev/null ||
    fail "Claude settings are not valid JSON"
jq -e . "$repo/private_dot_codex/private_hooks.json" >/dev/null ||
    fail "Codex hooks are not valid JSON"

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
[ "$(yq '.sandbox_mode' "$repo/private_dot_codex/agents/private_reviewer.toml")" = "read-only" ] ||
    fail "Codex reviewer must be mechanically read-only"
if grep -Eq 'session-start-context|post-edit-format|enforce-conventional-commits' \
    "$repo/private_dot_codex/private_hooks.json"; then
    fail "user-trusted Codex hooks must not execute checkout-controlled tasks"
fi

echo "==> validate instruction and skill compatibility links"
[ "$(cat "$repo/private_dot_codex/symlink_AGENTS.md")" = "../.claude/CLAUDE.md" ] ||
    fail "Codex AGENTS.md link does not target the global Claude guidance"
[ -L "$repo/.claude/skills" ] || fail "repository Claude skills path is not a symlink"
[ "$(readlink "$repo/.claude/skills")" = "../.agents/skills" ] ||
    fail "repository Claude skills path does not target .agents/skills"
[ "$(cat "$repo/private_dot_agents/skills/symlink_open-pr")" = "../../.claude/skills/open-pr" ] ||
    fail "open-pr compatibility link is wrong"
[ "$(cat "$repo/private_dot_agents/skills/symlink_rebase")" = "../../.claude/skills/rebase" ] ||
    fail "rebase compatibility link is wrong"
[ "$(cat "$repo/private_dot_agents/skills/symlink_standardize-repo")" = "../../.claude/skills/standardize-repo" ] ||
    fail "harmon-devkit standardize-repo compatibility link is wrong"

echo "==> validate Codex profile wrapper"
aliases_file="$repo/private_dot_dotfiles/private_dot_aliases"
stub_dir="$(mktemp -d)"
trap 'rm -rf "$stub_dir"' EXIT
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
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- gh -R owner/repo pr merge 123 | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "option-prefixed gh pr merge should require approval, got $decision"
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- gh --repo=owner/repo pr merge 123 | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "attached-option gh pr merge should require approval, got $decision"
else
    echo "SKIP: codex is unavailable; execpolicy parsing is covered on configured hosts"
fi

echo "==> Claude/Codex configuration OK"
