#!/usr/bin/env bash
# Validate personal AI harness configuration without touching $HOME.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
profile_template="$repo/private_dot_codex/modify_private_harmon-local.config.toml"
opencode_dir="$repo/dot_config/opencode"
opencode_config="$opencode_dir/opencode.jsonc"
opencode_tui="$opencode_dir/tui.jsonc"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

# The modify-template behaviour checks below skip when chezmoi is missing, so a
# local run without it still passes. CI installs a pinned chezmoi
# (.github/actions/setup, #133), so there a missing one is a broken runner,
# not a reason to drop the checks silently.
if [ "${CI:-}" = "true" ] && ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not installed in CI, so the modify-template behaviour checks cannot run"
fi

test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/home" "$test_tmp/config" "$test_tmp/data" \
    "$test_tmp/cache" "$test_tmp/state" "$test_tmp/config/opencode"
cp "$opencode_config" "$opencode_tui" "$test_tmp/config/opencode/"

# The local Codex profile is a chezmoi modify template (#71): its managed keys
# are the TOML literal handed to `fromToml`. Extract that block so the static
# checks below read exactly what chezmoi lays over the live file.
profile="$test_tmp/harmon-local.managed.toml"
awk '/fromToml `[[:space:]]*$/{grab=1; next} grab && /^` -}}[[:space:]]*$/{exit} grab' "$profile_template" >"$profile"
[ -s "$profile" ] || fail "could not find the managed TOML block in $profile_template"

opencode_test() {
    HOME="$test_tmp/home" \
        XDG_CONFIG_HOME="$test_tmp/config" \
        XDG_DATA_HOME="$test_tmp/data" \
        XDG_CACHE_HOME="$test_tmp/cache" \
        XDG_STATE_HOME="$test_tmp/state" \
        command opencode "$@"
}

echo "==> parse AI harness configuration"
# Claude Code user settings are a chezmoi modify template (#48) over two data
# files: enforced (re-asserted every apply) and seeded (set only when missing).
claude_enforced="$repo/.chezmoitemplates/claude-settings/enforced.json"
claude_seeded="$repo/.chezmoitemplates/claude-settings/seeded.json"
jq -e . "$claude_enforced" >/dev/null || fail "enforced Claude settings are not valid JSON"
jq -e . "$claude_seeded" >/dev/null || fail "seeded Claude settings are not valid JSON"
# Each owner holds exactly its keys: an omission, or a security-relevant key
# moved to the seeded (live-wins) file, fails here.
[ "$(jq -c 'keys' "$claude_enforced")" = \
    '["//","enabledPlugins","hooks","permissions","sandbox","skipDangerousModePermissionPrompt","statusLine"]' ] ||
    fail "the enforced Claude settings do not hold exactly the enforced keys"
[ "$(jq -c 'keys' "$claude_seeded")" = \
    '["agentPushNotifEnabled","effortLevel","feedbackDrafts","inputNeededNotifEnabled","model","modelSettings","preferredNotifChannel","remoteControlAtStartup","skipWorkflowUsageWarning","switchModelsOnFlag","tui","voice","voiceEnabled"]' ] ||
    fail "the seeded Claude settings do not hold exactly the seeded keys"
jq -e . "$repo/private_dot_codex/private_hooks.json" >/dev/null ||
    fail "Codex hooks are not valid JSON"
jq -e . "$repo/private_dot_gemini/config/hooks.json" >/dev/null ||
    fail "Gemini hooks are not valid JSON"
# The Antigravity CLI settings are a chezmoi modify template: the managed keys
# are the JSON literal handed to `fromJson`, with @HOME@ for the home directory.
antigravity_template="$repo/private_dot_gemini/antigravity-cli/modify_private_settings.json"
antigravity_managed="$test_tmp/antigravity.managed.json"
awk '/replace "@HOME@" \.chezmoi\.homeDir `[[:space:]]*$/{grab=1; next} grab && /^`\) -}}[[:space:]]*$/{exit} grab' "$antigravity_template" |
    sed 's|@HOME@|/Users/test|g' >"$antigravity_managed"
jq -e . "$antigravity_managed" >/dev/null || fail "Antigravity CLI managed settings are not valid JSON"
[ "$(jq -r '.statusLine.type' "$antigravity_managed")" = "command" ] ||
    fail "Antigravity CLI settings must configure command statusLine"
[ "$(jq -r '.model' "$antigravity_managed")" = "Gemini 3.8 Flash (High)" ] ||
    fail "Antigravity CLI settings must configure default model Gemini 3.8 Flash (High)"
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

[ "$(yq '.model' "$profile")" = "gpt-6.1-sol" ] ||
    fail "local Codex profile must use gpt-6.1-sol"
[ "$(yq '.model_reasoning_effort' "$profile")" = "medium" ] ||
    fail "local Codex profile must use medium reasoning"
[ "$(yq '.sandbox_mode' "$profile")" = "workspace-write" ] ||
    fail "local Codex profile must enable the workspace sandbox"
[ "$(yq '.approval_policy' "$profile")" = "on-request" ] ||
    fail "local Codex profile must use on-request approvals"
[ "$(yq '.project_doc_max_bytes' "$profile")" = "65536" ] ||
    fail "local Codex profile must load up to 64 KiB of project guidance"
# The managed view of the Claude settings: seeded defaults under the enforced keys.
claude_settings="$test_tmp/claude-settings.managed.json"
jq -s '.[0] * .[1]' "$claude_seeded" "$claude_enforced" >"$claude_settings"
[ "$(jq -r '.model' "$claude_settings")" = "opus" ] ||
    fail "Claude must default to the opus alias"
[ "$(jq -r '.modelSettings["claude-fable-5-1"].effortLevel' "$claude_settings")" = "high" ] ||
    fail "Claude Fable 5.1 must default to high effort"
[ "$(jq -r '.modelSettings["claude-opus-5-5"].effortLevel' "$claude_settings")" = "medium" ] ||
    fail "Claude Opus 5.5 must default to medium effort"
[ "$(jq -r '.modelSettings["claude-sonnet-5-5"].effortLevel' "$claude_settings")" = "medium" ] ||
    fail "Claude Sonnet 5.5 must default to medium effort"
# Booleans are compared as JSON booleans: Claude Code ignores a string "true".
jq -e '.remoteControlAtStartup == true' "$claude_settings" >/dev/null ||
    fail "Claude must start Remote Control with every session"
# Enabled, not enforced: the sandbox stays fail-open (a host where it cannot
# start runs Bash unsandboxed with a warning) and keeps the permission-gated
# per-command escape, by the maintainer's choice.
jq -e '.sandbox.enabled == true' "$claude_settings" >/dev/null ||
    fail "Claude must enable the Bash sandbox by default"
jq -e '.inputNeededNotifEnabled == true' "$claude_settings" >/dev/null ||
    fail "Claude must notify when it needs input"
[ "$(jq -r '.feedbackDrafts' "$claude_settings")" = "off" ] ||
    fail "Claude-drafted feedback must be off"
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

echo "==> validate the Codex profile modify template when chezmoi is available"
if command -v chezmoi >/dev/null 2>&1; then
    # Render the template the way `chezmoi apply` does, against a scratch home.
    render_profile() { # home-dir -> rendered profile on stdout
        chezmoi --source "$repo" --destination "$1" --config "$test_tmp/chezmoi.toml" \
            --persistent-state "$1.state" cat "$1/.codex/harmon-local.config.toml"
    }
    : >"$test_tmp/chezmoi.toml"
    seed_home="$test_tmp/codex-seed"
    mkdir -p "$seed_home/.codex"
    # A live file holding Codex's own runtime state and one drifted managed key.
    cat >"$seed_home/.codex/harmon-local.config.toml" <<'TOML'
model = "gpt-0-old"
model_reasoning_effort = "medium"
screen_reader_detection_done = true

[tui.model_availability_nux]
"gpt-6.1-sol" = 1

[hooks.state."/home/u/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:abc"

[hooks.state."browser@openai-bundled:plugin.json#hooks[0]:stop:0:0"]
trusted_hash = "sha256:def"
enabled = false

[projects."/home/u/git/example"]
trust_level = "trusted"
TOML
    # Renders go straight to files and are compared with cmp: command
    # substitution would strip trailing newlines and hide a byte difference.
    render_profile "$seed_home" >"$test_tmp/rendered.toml" ||
        fail "the Codex profile modify template did not render"
    [ "$(yq -p toml -oy '.model' "$test_tmp/rendered.toml")" = "$(yq '.model' "$profile")" ] ||
        fail "the Codex profile template did not re-assert the managed model over a drifted value"
    [ "$(yq -p toml -oy '.projects."/home/u/git/example".trust_level' "$test_tmp/rendered.toml")" = "trusted" ] ||
        fail "the Codex profile template dropped Codex's project trust"
    [ "$(yq -p toml -oy '.hooks.state."browser@openai-bundled:plugin.json#hooks[0]:stop:0:0".enabled' "$test_tmp/rendered.toml")" = "false" ] ||
        fail "the Codex profile template dropped a disabled hook's state (it would silently re-enable)"
    [ "$(yq -p toml -oy '.tui.model_availability_nux."gpt-6.1-sol"' "$test_tmp/rendered.toml")" = "1" ] ||
        fail "the Codex profile template dropped Codex's notice counters"
    [ "$(yq -p toml -oy '.screen_reader_detection_done' "$test_tmp/rendered.toml")" = "true" ] ||
        fail "the Codex profile template dropped an unmanaged top-level key"
    # Once every managed value holds, the file is kept byte-for-byte, so Codex's
    # own formatting never shows up as chezmoi drift.
    cp "$test_tmp/rendered.toml" "$seed_home/.codex/harmon-local.config.toml"
    render_profile "$seed_home" >"$test_tmp/stable.toml"
    cmp -s "$test_tmp/stable.toml" "$test_tmp/rendered.toml" ||
        fail "re-rendering an up-to-date Codex profile changed it (permanent drift)"
    sed 's/^approval_policy = .*/approval_policy = "on-request"   # reformatted by Codex/' \
        "$test_tmp/rendered.toml" >"$seed_home/.codex/harmon-local.config.toml"
    render_profile "$seed_home" >"$test_tmp/reformatted.toml"
    cmp -s "$test_tmp/reformatted.toml" "$seed_home/.codex/harmon-local.config.toml" ||
        fail "a reformatted but up-to-date Codex profile was rewritten instead of kept"
    # No live file yet: the managed defaults alone.
    fresh_home="$test_tmp/codex-fresh"
    mkdir -p "$fresh_home"
    render_profile "$fresh_home" >"$test_tmp/fresh.toml" || fail "the Codex profile template did not render without a live file"
    # With no live file the render is exactly the managed block: every owned
    # default, nothing else.
    python3 - "$test_tmp/fresh.toml" "$profile" <<'PY_FRESH' ||
import sys, tomllib
fresh, managed = (tomllib.load(open(p, "rb")) for p in sys.argv[1:3])
sys.exit(0 if fresh == managed else 1)
PY_FRESH
        fail "a fresh Codex profile does not render exactly the managed defaults"
    # Over a live file, every managed key holds its managed value.
    python3 - "$test_tmp/rendered.toml" "$profile" <<'PY_MANAGED' ||
import sys, tomllib
out, managed = (tomllib.load(open(p, "rb")) for p in sys.argv[1:3])
def held(m, o):
    return all(held(v, o.get(k, {})) if isinstance(v, dict) else o.get(k) == v for k, v in m.items())
sys.exit(0 if held(managed, out) else 1)
PY_MANAGED
        fail "a rendered Codex profile does not hold every managed value"
else
    echo "    chezmoi not installed; skipping the modify-template behaviour checks"
fi

echo "==> validate the Antigravity settings modify template when chezmoi is available"
if command -v chezmoi >/dev/null 2>&1; then
    render_antigravity() { # home-dir -> rendered settings on stdout
        chezmoi --source "$repo" --destination "$1" --config "$test_tmp/chezmoi.toml" \
            --persistent-state "$1.state" cat "$1/.gemini/antigravity-cli/settings.json"
    }
    : >"$test_tmp/chezmoi.toml"
    ag_home="$test_tmp/ag-seed"
    mkdir -p "$ag_home/.gemini/antigravity-cli"
    # A live file with a drifted managed key, an extra deny the managed list
    # does not carry, an unmanaged key, and workspaces Antigravity trusted.
    # .chezmoi.homeDir is the real home whatever --destination says, so the
    # managed workspaces render under $HOME (rendered text only; nothing there
    # is written).
    jq -n --arg h "$HOME" '{model: "Gemini 0 Old", someRuntimeKey: 7,
        permissions: {deny: ["command(extra)"], allow: ["command(ls)"]},
        statusLine: {command: "old", runtimeHint: "keep"},
        trustedWorkspaces: [($h + "/git/harmon-dotfiles"), "/elsewhere/repo-a", "/elsewhere/repo-b"]}' \
        >"$ag_home/.gemini/antigravity-cli/settings.json"
    render_antigravity "$ag_home" >"$test_tmp/ag.out" || fail "the Antigravity settings template did not render"
    [ "$(jq -r '.model' "$test_tmp/ag.out")" = "Gemini 3.8 Flash (High)" ] ||
        fail "the Antigravity template did not re-assert the managed model"
    [ "$(jq -r '.someRuntimeKey' "$test_tmp/ag.out")" = "7" ] ||
        fail "the Antigravity template dropped an unmanaged key"
    # trustedWorkspaces: exactly the managed baseline in order, then the
    # workspaces Antigravity added in their order, with no duplicate.
    jq -e --arg h "$HOME" --slurpfile m "$antigravity_managed" '
        .trustedWorkspaces == ([$m[0].trustedWorkspaces[] | if startswith("/Users/test") then $h + .[11:] else . end]
            + ["/elsewhere/repo-a", "/elsewhere/repo-b"])' "$test_tmp/ag.out" >/dev/null ||
        fail "the Antigravity trustedWorkspaces are not the managed baseline then Antigravity's own, in order"
    # The deny list is authoritative: exactly the managed list.
    jq -e --slurpfile m "$antigravity_managed" '.permissions.deny == $m[0].permissions.deny' \
        "$test_tmp/ag.out" >/dev/null ||
        fail "the Antigravity deny list is not exactly the managed list"
    # Unmanaged members of managed objects survive a correction.
    jq -e '.permissions.allow == ["command(ls)"] and .statusLine.runtimeHint == "keep"
        and (.statusLine.command | endswith("/.gemini/antigravity-cli/statusline.sh"))' \
        "$test_tmp/ag.out" >/dev/null ||
        fail "the Antigravity template replaced a managed object wholesale and lost nested runtime state"
    # Applied, the settings are private: the source carries the private_ attribute.
    chezmoi --source "$repo" --destination "$ag_home" --config "$test_tmp/chezmoi.toml" \
        --persistent-state "$ag_home.state" apply --force "$ag_home/.gemini/antigravity-cli/settings.json" ||
        fail "chezmoi could not apply the Antigravity settings to a scratch home"
    ag_mode="$(stat -c '%a' "$ag_home/.gemini/antigravity-cli/settings.json" 2>/dev/null ||
        stat -f '%Lp' "$ag_home/.gemini/antigravity-cli/settings.json")"
    [ "$ag_mode" = "600" ] || fail "applied Antigravity settings have mode $ag_mode, expected 600"
    # Up to date: kept byte-for-byte.
    cp "$test_tmp/ag.out" "$ag_home/.gemini/antigravity-cli/settings.json"
    render_antigravity "$ag_home" >"$test_tmp/ag.stable"
    cmp -s "$test_tmp/ag.stable" "$test_tmp/ag.out" ||
        fail "re-rendering up-to-date Antigravity settings changed them (permanent drift)"
    # Up to date but in Antigravity's own layout (here: compact): kept as-is.
    jq -c . "$test_tmp/ag.out" >"$ag_home/.gemini/antigravity-cli/settings.json"
    render_antigravity "$ag_home" >"$test_tmp/ag.compact"
    cmp -s "$test_tmp/ag.compact" "$ag_home/.gemini/antigravity-cli/settings.json" ||
        fail "reformatted but up-to-date Antigravity settings were rewritten instead of kept"
    # No live file: the managed settings alone, with the baseline workspaces.
    ag_fresh="$test_tmp/ag-fresh"
    mkdir -p "$ag_fresh"
    render_antigravity "$ag_fresh" | sed "s|$HOME|/Users/test|g" >"$test_tmp/ag.fresh" ||
        fail "the Antigravity template did not render without a live file"
    jq -e --slurpfile m "$antigravity_managed" '. == $m[0]' "$test_tmp/ag.fresh" >/dev/null ||
        fail "fresh Antigravity settings do not render exactly the managed settings"
else
    echo "    chezmoi not installed; skipping the Antigravity modify-template behaviour checks"
fi

echo "==> validate the Claude settings modify template when chezmoi is available"
if command -v chezmoi >/dev/null 2>&1; then
    render_claude() { # home-dir -> rendered settings on stdout
        chezmoi --source "$repo" --destination "$1" --config "$test_tmp/chezmoi.toml" \
            --persistent-state "$1.state" cat "$1/.claude/settings.json"
    }
    : >"$test_tmp/chezmoi.toml"
    cl_home="$test_tmp/claude-seed"
    mkdir -p "$cl_home/.claude"
    # A live file as Claude Code leaves it: /model changed, a seeded key
    # missing, an extra allow rule, a plugin installed in-session, a managed
    # plugin switched off, hooks edited, and autoMode written by setup.
    jq --arg m "claude-sonnet-5-5" '
        .model = $m
        | del(.feedbackDrafts)
        | .permissions.allow += ["Bash(rm:*)"]
        | .permissions.additionalDirectories = ["/elsewhere"]
        | .enabledPlugins["extra@somewhere"] = true
        | .enabledPlugins[(.enabledPlugins | keys[0])] = false
        | .hooks = {}
        | .autoMode = {environment: ["### Org-wide", "**Trusted repo**: example"]}
        | .remoteControlAtStartup = false
        | .voice.enabled = false
        | .disableAllHooks = true
        | .enableAllProjectMcpServers = true
        | .env = {CLAUDE_CODE_SIMPLE: "1", CLAUDE_CODE_SAFE_MODE: "1"}
        | .apiKeyHelper = "/tmp/key.sh"
        | .awsAuthRefresh = "aws sso login"
        | .awsCredentialExport = "/tmp/creds.sh"
        | .otelHeadersHelper = "/tmp/otel.sh"
        | .processWrapper = "/tmp/wrap.sh"
        | .fileSuggestion = {command: "/tmp/suggest.sh"}
        | .gcpAuthRefresh = "gcloud auth login"
        | .proxyAuthHelper = "/tmp/proxy.sh"
        | .enabledMcpjsonServers = ["evil"]
        | .skipWebFetchPreflight = true
        | .someFutureSetting = 1' \
        "$claude_settings" >"$cl_home/.claude/settings.json"
    render_claude "$cl_home" >"$test_tmp/cl.out" || fail "the Claude settings template did not render"
    [ "$(jq -r '.model' "$test_tmp/cl.out")" = "claude-sonnet-5-5" ] ||
        fail "the Claude settings template reverted an in-session /model change (seeded keys must keep the live value)"
    [ "$(jq -r '.feedbackDrafts' "$test_tmp/cl.out")" = "$(jq -r '.feedbackDrafts' "$claude_seeded")" ] ||
        fail "the Claude settings template did not seed a missing preference"
    jq -e --slurpfile e "$claude_enforced" '.permissions == $e[0].permissions and .hooks == $e[0].hooks' \
        "$test_tmp/cl.out" >/dev/null ||
        fail "Claude permissions and hooks must be exactly the enforced ones (authoritative)"
    jq -e '.enabledPlugins["extra@somewhere"] == true' "$test_tmp/cl.out" >/dev/null ||
        fail "the Claude settings template dropped an in-session plugin"
    jq -e --slurpfile e "$claude_enforced" '. as $o
        | $e[0].enabledPlugins | to_entries | all(.value as $v | $o.enabledPlugins[.key] == $v)' \
        "$test_tmp/cl.out" >/dev/null ||
        fail "the Claude settings template did not force the managed plugins back to their managed state"
    jq -e '.autoMode.environment[1] == "**Trusted repo**: example"' "$test_tmp/cl.out" >/dev/null ||
        fail "the Claude settings template dropped Claude Code's own autoMode block"
    # Seeding is by key presence: a preference turned off stays off.
    jq -e '.remoteControlAtStartup == false and .voice.enabled == false' "$test_tmp/cl.out" >/dev/null ||
        fail "the Claude settings template re-enabled a preference the user turned off"
    # Allow list: only enforced, seeded and runtime-owned keys survive, so no
    # control kill-switch, command helper or unknown setting rides along.
    jq -e -n --slurpfile o "$test_tmp/cl.out" --slurpfile e "$claude_enforced" --slurpfile s "$claude_seeded" '
        ([$o[0] | keys[]] - [$e[0] | keys[]] - [$s[0] | keys[]] - ["autoMode"]) == []' >/dev/null ||
        fail "a Claude setting outside the allow list (enforced, seeded, autoMode) passed through"
    # Up to date, and up to date in Claude Code's own key order: kept as-is.
    cp "$test_tmp/cl.out" "$cl_home/.claude/settings.json"
    render_claude "$cl_home" >"$test_tmp/cl.stable"
    cmp -s "$test_tmp/cl.stable" "$test_tmp/cl.out" ||
        fail "re-rendering up-to-date Claude settings changed them (permanent drift)"
    jq -S . "$test_tmp/cl.out" >"$cl_home/.claude/settings.json"
    render_claude "$cl_home" >"$test_tmp/cl.sorted"
    cmp -s "$test_tmp/cl.sorted" "$cl_home/.claude/settings.json" ||
        fail "reordered but up-to-date Claude settings were rewritten instead of kept"
    # No live file: exactly the managed settings.
    cl_fresh="$test_tmp/claude-fresh"
    mkdir -p "$cl_fresh"
    render_claude "$cl_fresh" >"$test_tmp/cl.fresh" || fail "the Claude settings template did not render without a live file"
    jq -e --slurpfile m "$claude_settings" '. == $m[0]' "$test_tmp/cl.fresh" >/dev/null ||
        fail "fresh Claude settings do not render exactly the managed settings"
    # Applied, the settings are private.
    chezmoi --source "$repo" --destination "$cl_home" --config "$test_tmp/chezmoi.toml" \
        --persistent-state "$cl_home.state" apply --force "$cl_home/.claude/settings.json" ||
        fail "chezmoi could not apply the Claude settings to a scratch home"
    cl_mode="$(stat -c '%a' "$cl_home/.claude/settings.json" 2>/dev/null ||
        stat -f '%Lp' "$cl_home/.claude/settings.json")"
    [ "$cl_mode" = "600" ] || fail "applied Claude settings have mode $cl_mode, expected 600"
else
    echo "    chezmoi not installed; skipping the Claude settings modify-template behaviour checks"
fi

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
out=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'{"workspace":{"current_dir":"/"},"context_window":{"used_percentage":24,"context_window_size":1000000},"model":{"display_name":"Gemini 3.7 Flash (High)"},"conversation_id":"34ee01b6-2f37-4fe7"}')
case "$out" in *' 24%'*) ;; *) fail "Antigravity statusline expected 24%, got: $out" ;; esac
case "$out" in *'760k left'*) ;; *) fail "Antigravity statusline expected '760k left', got: $out" ;; esac
case "$out" in *'Gemini 3.7 Flash (High)'*) ;; *) fail "Antigravity statusline expected model name, got: $out" ;; esac
case "$out" in *'34ee01b6'*) ;; *) fail "Antigravity statusline expected session id, got: $out" ;; esac

# 2. Absent context renders 'context n/a' and never a false 0% gauge
out_absent=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'{"workspace":{"current_dir":"/"},"model":{"display_name":"Gemini 3.1 Pro"}}')
case "$out_absent" in *'context n/a'*) ;; *) fail "Antigravity statusline expected 'context n/a' for absent context, got: $out_absent" ;; esac
case "$out_absent" in *'0%'*) fail "Antigravity statusline rendered false 0% for absent context: $out_absent" ;; esac

# 3. Empty payload degrades gracefully
out_empty=$(NO_COLOR=1 STATUSLINE_HYPERLINK=0 bash "$agy_sl" <<<'')
[ -n "$out_empty" ] || fail "Antigravity statusline returned empty output on empty payload"

echo "==> AI harness configuration OK"
