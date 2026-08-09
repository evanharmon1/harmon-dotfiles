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
    yq '.' "$toml" >/dev/null || fail "invalid TOML: $toml"
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

echo "==> validate Codex policy rules when the CLI is available"
if command -v codex >/dev/null 2>&1; then
    decision="$(codex execpolicy check --rules "$repo/private_dot_codex/rules/private_harmon.rules" -- git push origin main | jq -r '.decision')"
    [ "$decision" = "prompt" ] || fail "git push should require approval, got $decision"
else
    echo "SKIP: codex is unavailable; execpolicy parsing is covered on configured hosts"
fi

echo "==> Claude/Codex configuration OK"
