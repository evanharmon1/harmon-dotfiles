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

# Resolve paths through the longest existing parent. This canonicalizes macOS
# aliases such as /etc -> /private/etc even when the final path does not exist.
normalize_path() {
    local path="$1" parent suffix next
    case "$path" in
    /*) ;;
    ~/*) path="$HOME/${path#\~/}" ;;
    *) path="${CLAUDE_PROJECT_DIR:-$PWD}/$path" ;;
    esac

    parent="$(dirname -- "$path")"
    suffix="$(basename -- "$path")"
    while [[ ! -d "$parent" ]]; do
        next="$(dirname -- "$parent")"
        [[ "$next" != "$parent" ]] || break
        suffix="$(basename -- "$parent")/$suffix"
        parent="$next"
    done
    if [[ -d "$parent" ]]; then
        path="$(cd -- "$parent" && pwd -P)/$suffix"
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        path="$(realpath -- "$path")"
    fi
    printf '%s\n' "$path"
}

resolved_path="$(normalize_path "$file_path")"

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
    if [[ "$file_path" == *"$pattern"* || "$resolved_path" == *"$pattern"* ]]; then
        echo "protect-files: blocked write to '$file_path' (matches protected pattern '$pattern')" >&2
        exit 2
    fi
done

for system_dir in "$(normalize_path /etc/claude-code)" "$(normalize_path /etc/codex)"; do
    if [[ "$resolved_path" == "$system_dir" || "$resolved_path" == "$system_dir/"* ]]; then
        echo "protect-files: blocked write to '$file_path' (machine-level AI config)" >&2
        exit 2
    fi
done

# Protect the user-level managed Codex config without blocking a repository's
# version-controlled .codex/config.toml. Codex apply_patch paths can be relative
# to the session cwd, so compare the normalized candidate computed above.
codex_config="$(cd -- "$HOME" && pwd -P)/.codex/config.toml"
if [[ -e "$codex_config" || -L "$codex_config" ]]; then
    codex_config="$(realpath -- "$codex_config")"
fi
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
