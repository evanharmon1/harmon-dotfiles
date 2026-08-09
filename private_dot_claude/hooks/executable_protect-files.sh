#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook for Edit|Write|MultiEdit.
#
# Blocks AI modification of sensitive or generated files: secrets, lockfiles,
# git internals, dependency dirs, binary assets, terraform state, ansible vault,
# and machine-level Claude/Codex managed settings. Exit 2 tells Claude Code to refuse the
# tool call and surface the stderr message back to the model.
set -euo pipefail

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"
[[ -n "$file_path" ]] || exit 0

# Substring patterns — matched anywhere in the path.
protected=(
    ".env"
    "uv.lock"
    "package-lock.json"
    ".git/"
    "node_modules/"
    "dist/"
    ".terraform/"
    ".tfstate"
    ".claude/settings.json"
    "/etc/claude-code/"
    "/etc/codex/"
)

for pattern in "${protected[@]}"; do
    if [[ "$file_path" == *"$pattern"* ]]; then
        echo "protect-files: blocked write to '$file_path' (matches protected pattern '$pattern')" >&2
        exit 2
    fi
done

# Protect the user-level managed Codex config without blocking a repository's
# version-controlled .codex/config.toml. Codex apply_patch paths can be relative
# to the session cwd, so normalize an existing parent directory before comparing.
resolved_path="$file_path"
case "$resolved_path" in
/*) ;;
~/*) resolved_path="$HOME/${resolved_path#\~/}" ;;
*) resolved_path="${CLAUDE_PROJECT_DIR:-$PWD}/$resolved_path" ;;
esac
resolved_parent="$(dirname -- "$resolved_path")"
if [[ -d "$resolved_parent" ]]; then
    resolved_path="$(cd -- "$resolved_parent" && pwd -P)/$(basename -- "$resolved_path")"
fi
if [[ -e "$resolved_path" || -L "$resolved_path" ]]; then
    resolved_path="$(realpath -- "$resolved_path")"
fi
codex_config="$(cd -- "$HOME" && pwd -P)/.codex/config.toml"
if [[ "$resolved_path" == "$codex_config" ]]; then
    echo "protect-files: blocked write to '$file_path' (machine-level Codex config)" >&2
    exit 2
fi

# Suffix patterns — binary assets that shouldn't be hand-edited.
case "$file_path" in
*/.git | .git)
    echo "protect-files: blocked write to '$file_path' (exact .git file)" >&2
    exit 2
    ;;
*.png | *.jpg | *.jpeg | *.webp | *.gif | *.ico | *.pdf | *.pem | *.key)
    echo "protect-files: blocked write to '$file_path' (binary asset or secret)" >&2
    exit 2
    ;;
esac

exit 0
