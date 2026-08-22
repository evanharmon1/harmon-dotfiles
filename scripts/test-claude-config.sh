#!/usr/bin/env bash
# test-claude-config.sh — behavioral test for the chezmoi run script that
# asserts `remoteControlAtStartup: true` in ~/.claude.json (issue #67).
#
# Run via `task test:claude-config`.
#
# Hermetic: every case runs the script under its own throwaway HOME (or
# CLAUDE_CONFIG_DIR), so the developer's real ~/.claude.json is never read or
# written. That matters more than usual here — the file under test holds live
# Claude Code runtime state.
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
script="$repo/.chezmoiscripts/run_after_configure-claude-remote-control.sh"

fail() {
    echo "TEST FAIL: $*" >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# BSD (macOS) and GNU (CI) stat spell the octal-mode query differently.
file_mode() {
    stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

# Each case gets a fresh HOME under $TMP; returns its path on stdout.
new_home() {
    local dir
    dir="$(mktemp -d "$TMP/home.XXXXXX")"
    printf '%s\n' "$dir"
}

echo "==> missing file is created with the key, mode 0600"
home="$(new_home)"
out="$(HOME="$home" CLAUDE_CONFIG_DIR="" bash "$script")"
[ -f "$home/.claude.json" ] || fail "config file was not created"
jq -e '.remoteControlAtStartup == true' "$home/.claude.json" >/dev/null ||
    fail "remoteControlAtStartup was not set to true in a fresh file"
[ "$(file_mode "$home/.claude.json")" = "600" ] ||
    fail "fresh config file must be mode 0600, got $(file_mode "$home/.claude.json")"
[ "$out" = "==> Enabled Claude Code Remote Control (remoteControlAtStartup=true) in $home/.claude.json" ] ||
    fail "unexpected stdout for a fresh file: $out"

echo "==> existing keys are preserved and the mode is kept"
home="$(new_home)"
printf '%s\n' '{"numStartups":5,"tipsHistory":{"a":1},"remoteControlAtStartup":false}' \
    >"$home/.claude.json"
chmod 640 "$home/.claude.json"
HOME="$home" bash "$script" >/dev/null
jq -e '.remoteControlAtStartup == true' "$home/.claude.json" >/dev/null ||
    fail "remoteControlAtStartup was not flipped to true"
[ "$(jq -r '.numStartups' "$home/.claude.json")" = "5" ] || fail "numStartups was not preserved"
[ "$(jq -c '.tipsHistory' "$home/.claude.json")" = '{"a":1}' ] || fail "tipsHistory was not preserved"
[ "$(file_mode "$home/.claude.json")" = "640" ] ||
    fail "existing mode must be preserved, got $(file_mode "$home/.claude.json")"

echo "==> already-true is a silent no-op"
home="$(new_home)"
printf '%s\n' '{"remoteControlAtStartup":true,"numStartups":2}' >"$home/.claude.json"
before="$(cat "$home/.claude.json")"
out="$(HOME="$home" bash "$script" 2>"$TMP/noop.err")"
[ -z "$out" ] || fail "an already-configured file must print nothing, got: $out"
[ ! -s "$TMP/noop.err" ] || fail "an already-configured file must not warn: $(cat "$TMP/noop.err")"
[ "$(cat "$home/.claude.json")" = "$before" ] || fail "an already-configured file must be byte-identical"

echo "==> invalid JSON is left untouched with a warning"
home="$(new_home)"
printf '%s' '{not json' >"$home/.claude.json"
HOME="$home" bash "$script" >/dev/null 2>"$TMP/invalid.err" ||
    fail "invalid JSON must still exit 0"
[ "$(cat "$home/.claude.json")" = '{not json' ] || fail "invalid JSON file was modified"
grep -q "not valid JSON" "$TMP/invalid.err" || fail "no warning for invalid JSON"

echo "==> a missing jq warns and changes nothing"
home="$(new_home)"
printf '%s\n' '{"numStartups":1}' >"$home/.claude.json"
before="$(cat "$home/.claude.json")"
shim="$TMP/shim-bin"
mkdir -p "$shim"
for tool in bash mktemp mv rm chmod stat mkdir dirname cat cp; do
    tool_path="$(command -v "$tool")" || fail "missing test dependency: $tool"
    ln -sf "$tool_path" "$shim/$tool"
done
[ ! -e "$shim/jq" ] || fail "the jq-less shim must not contain jq"
HOME="$home" PATH="$shim" bash "$script" >/dev/null 2>"$TMP/nojq.err" ||
    fail "a missing jq must still exit 0"
[ "$(cat "$home/.claude.json")" = "$before" ] || fail "config was modified without jq"
grep -q "jq not found" "$TMP/nojq.err" || fail "no warning when jq is missing"

echo "==> CLAUDE_CONFIG_DIR wins over HOME"
home="$(new_home)"
config_dir="$(mktemp -d "$TMP/cfg.XXXXXX")"
HOME="$home" CLAUDE_CONFIG_DIR="$config_dir" bash "$script" >/dev/null
jq -e '.remoteControlAtStartup == true' "$config_dir/.claude.json" >/dev/null ||
    fail "CLAUDE_CONFIG_DIR target was not configured"
[ ! -e "$home/.claude.json" ] || fail "HOME must not be touched when CLAUDE_CONFIG_DIR is set"

echo "==> an unwritable config dir warns and exits 0 (skipped as root)"
if [ "$(id -u)" != "0" ]; then
    home="$(new_home)"
    printf '%s\n' '{"remoteControlAtStartup":false}' >"$home/.claude.json"
    before="$(cat "$home/.claude.json")"
    chmod 500 "$home"
    rc=0
    HOME="$home" bash "$script" >"$TMP/ro.out" 2>"$TMP/ro.err" || rc=$?
    chmod 700 "$home"
    [ "$rc" = "0" ] || fail "an unwritable config dir must still exit 0, got $rc"
    [ ! -s "$TMP/ro.out" ] || fail "an unwritable config dir must not claim success: $(cat "$TMP/ro.out")"
    grep -q "Warning" "$TMP/ro.err" || fail "no warning for an unwritable config dir"
    [ "$(cat "$home/.claude.json")" = "$before" ] || fail "config was modified in an unwritable dir"
    [ -z "$(find "$home" -name '.claude.json.*' 2>/dev/null)" ] || fail "temp file left behind in an unwritable dir"
fi

echo "==> a symlinked config updates the target and keeps the link"
home="$(new_home)"
store="$(mktemp -d "$TMP/store.XXXXXX")"
printf '%s\n' '{"numStartups":3}' >"$store/.claude.json"
chmod 600 "$store/.claude.json"
ln -s "$store/.claude.json" "$home/.claude.json"
HOME="$home" bash "$script" >/dev/null
[ -L "$home/.claude.json" ] || fail "the symlink was replaced by a regular file"
jq -e '.remoteControlAtStartup == true' "$store/.claude.json" >/dev/null ||
    fail "the symlink target was not updated"
[ "$(jq -r '.numStartups' "$store/.claude.json")" = "3" ] || fail "symlink target keys were not preserved"
[ "$(file_mode "$store/.claude.json")" = "600" ] ||
    fail "symlink target mode must be preserved, got $(file_mode "$store/.claude.json")"

echo "==> a string \"true\" is replaced with boolean true"
home="$(new_home)"
printf '%s\n' '{"remoteControlAtStartup":"true"}' >"$home/.claude.json"
HOME="$home" bash "$script" >/dev/null
[ "$(jq -c '.remoteControlAtStartup' "$home/.claude.json")" = "true" ] ||
    fail "string \"true\" was not replaced with boolean true"

echo "==> a directory at the config path warns and writes nothing"
home="$(new_home)"
mkdir "$home/.claude.json"
HOME="$home" bash "$script" >"$TMP/dir.out" 2>"$TMP/dir.err" || fail "a directory config path must still exit 0"
[ -d "$home/.claude.json" ] || fail "the directory was replaced"
[ -z "$(ls -A "$home/.claude.json")" ] || fail "a file was written inside the directory"
[ ! -s "$TMP/dir.out" ] || fail "a directory config path must not claim success"
grep -q "not a regular file" "$TMP/dir.err" || fail "no warning for a directory config path"

echo "==> a file rewritten mid-update is left alone (concurrent-writer guard)"
home="$(new_home)"
printf '%s\n' '{"remoteControlAtStartup":false}' >"$home/.claude.json"
shim="$TMP/shim-jq"
mkdir -p "$shim"
# A jq wrapper that simulates Claude Code writing the file between the read
# and the rename: it runs the real jq, then replaces the config with newer state.
cat >"$shim/jq" <<SHIM
#!/usr/bin/env bash
out="\$("$(command -v jq)" "\$@")" || exit \$?
printf '%s\\n' "\$out"
if [ "\${1:-}" != "empty" ] && [ "\${1:-}" != "-e" ]; then
    printf '%s\\n' '{"remoteControlAtStartup":false,"newer":1}' >"$home/.claude.json.swap"
    mv "$home/.claude.json.swap" "$home/.claude.json"
fi
SHIM
chmod +x "$shim/jq"
rc=0
HOME="$home" PATH="$shim:$PATH" bash "$script" >"$TMP/race.out" 2>"$TMP/race.err" || rc=$?
[ "$rc" = "0" ] || fail "a concurrent rewrite must still exit 0, got $rc"
[ "$(jq -r '.newer' "$home/.claude.json")" = "1" ] || fail "the newer concurrent state was overwritten"
[ ! -s "$TMP/race.out" ] || fail "a skipped update must not claim success: $(cat "$TMP/race.out")"
grep -q "changed while updating" "$TMP/race.err" || fail "no warning for a concurrent rewrite"
[ -z "$(find "$home" -name '.claude.json.*' 2>/dev/null)" ] || fail "temp file left behind after a skipped update"

echo "TEST PASS: claude remote-control run script"
