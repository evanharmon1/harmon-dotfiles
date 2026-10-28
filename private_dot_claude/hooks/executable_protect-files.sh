#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook for Edit|Write|MultiEdit.
#
# Blocks AI modification of sensitive files: credentials, secrets, Terraform
# state, Git control internals, and machine-level Claude/Codex managed settings.
# Permitted Git exceptions are dev-flow working state under
# <common>/dev-flow-v2/ and the deferred-findings root reported by Git.
# Exit 2 tells Claude Code to refuse the tool call and surface the stderr message back to the model.
set -euo pipefail

input="$(cat)"
# Preserve trailing controls so command substitution cannot erase them.
file_path="$(printf '%s' "$input" | jq -j '.tool_input.file_path // ""' && printf '.')"
file_path="${file_path%.}"
[[ -n "$file_path" ]] || exit 0

# Line-oriented path parsing cannot safely compare control characters.
refuse_control_paths() {
    local path
    for path in "$@"; do
        if [[ "$path" =~ [[:cntrl:]] ]]; then
            echo "protect-files: blocked write to '$file_path' (control character in path)" >&2
            exit 2
        fi
    done
}
refuse_control_paths "$file_path" "${CLAUDE_PROJECT_DIR:-$PWD}"

# Resolve paths through the longest existing parent. This canonicalizes macOS
# aliases such as /etc -> /private/etc even when the final path does not exist.
normalize_path() {
    local path="$1" parent suffix next
    local project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
    case "$project_dir" in
    /*) ;;
    *) project_dir="$PWD/$project_dir" ;;
    esac
    case "$path" in
    /*) ;;
    ~/*) path="$HOME/${path#\~/}" ;;
    *) path="$project_dir/$path" ;;
    esac

    # Collapse lexical aliases before the gitlink component. Leave its suffix
    # untouched for realpath below: it can contain symlink-plus-parent traversal.
    # Likewise, do not cancel a symlink before .. in the prefix.
    local candidate remaining lexical component
    local -a normalized=()
    # Normalize both operands identically, including project-dir trailing aliases.
    for candidate in "$path" "$project_dir"; do
        remaining="$candidate"
        lexical=""
        while [[ -n "$remaining" ]]; do
            component="${remaining%%/*}"
            if [[ "$remaining" == */* ]]; then
                remaining="${remaining#*/}"
            else
                remaining=""
            fi
            case "$component" in
            "" | .) ;;
            ..)
                if [[ -L "$lexical" ]]; then
                    lexical="$lexical/.."
                    [[ -z "$remaining" ]] || lexical="$lexical/$remaining"
                    break
                fi
                lexical="${lexical%/*}"
                ;;
            .git)
                lexical="$lexical/.git"
                [[ -z "$remaining" ]] || lexical="$lexical/$remaining"
                break
                ;;
            *) lexical="$lexical/$component" ;;
            esac
        done
        normalized+=("${lexical:-/}")
    done
    path="${normalized[0]}"
    project_dir="${normalized[1]}"

    # In a git worktree, .git is a gitlink file pointing to the main repo gitdir.
    # If the path references .git/... relative to a worktree containing a .git file,
    # resolve the .git component to the common git directory.
    if [[ -f "$project_dir/.git" && ("$path" == "$project_dir/.git" || "$path" == "$project_dir/.git/"*) ]]; then
        local git_common
        git_common="$(git -C "$project_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || true
        if [[ -n "$git_common" ]]; then
            case "$git_common" in
            /*) ;;
            *) git_common="$project_dir/$git_common" ;;
            esac
            if command -v python3 >/dev/null 2>&1; then
                git_common="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$git_common" 2>/dev/null)" || true
            else
                git_common="$(realpath "$git_common" 2>/dev/null)" || true
            fi
            if [[ -n "$git_common" ]]; then
                path="$git_common${path#"$project_dir/.git"}"
            fi
        fi
    fi

    # Resolve symlinks and parent components using filesystem semantics so
    # symlink-plus-parent traversal attacks (e.g. .git/dev-flow-v2/link/../victim)
    # resolve to their real target before matching.
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$path"
        return 0
    fi

    # Fallback when python3 is unavailable
    parent="$(dirname -- "$path")"
    suffix="$(basename -- "$path")"
    while [[ ! -d "$parent" ]]; do
        next="$(dirname -- "$parent")"
        [[ "$next" != "$parent" ]] || break
        suffix="$(basename -- "$parent")/$suffix"
        parent="$next"
    done
    if [[ -d "$parent" ]]; then
        path="$(cd -P -- "$parent" && pwd -P)/$suffix"
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        path="$(realpath -- "$path")"
    fi
    printf '%s\n' "$path"
}

resolved_path="$(normalize_path "$file_path" && printf '.')"
resolved_path="${resolved_path%$'\n.'}"
refuse_control_paths "$resolved_path"

# Substring patterns — matched anywhere in the path.
protected=(
    ".claude/settings.json"
    "/etc/claude-code/"
    "/etc/codex/"
    ".terraform/"
    ".tfstate"
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

# Git internals protection with carved-out dev-flow working directories.
# A .git/ write is allowed only when its fully resolved real path lies under
# <common>/dev-flow-v2/ or Git's deferred-findings root (computed at call time
# from the target path's nearest existing directory). Compared component by
# component: no globbing, no substring
# or suffix matching. Anything else under a .git/ directory is refused, and so is
# any path whose root cannot be computed (fail closed). The .git component match
# is case-insensitive to prevent case-folding bypasses on case-insensitive filesystems.
is_git_path() {
    local lower
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
    */.git/* | */.git | .git | .git/*) return 0 ;;
    *) return 1 ;;
    esac
}

check_git_invariant() {
    local target="$1"
    local root="$2"

    local -a target_parts common_parts
    local IFS="/"
    read -r -a target_parts <<<"$target"
    read -r -a common_parts <<<"$root"
    unset IFS

    local -a t_clean=() c_clean=()
    local part
    for part in "${target_parts[@]}"; do
        [[ -n "$part" ]] && t_clean+=("$part")
    done
    for part in "${common_parts[@]}"; do
        [[ -n "$part" ]] && c_clean+=("$part")
    done

    local c_len="${#c_clean[@]}"
    local t_len="${#t_clean[@]}"

    if ((t_len < c_len)); then
        return 1
    fi

    local i
    for ((i = 0; i < c_len; i++)); do
        if [[ "${t_clean[i]}" != "${c_clean[i]}" ]]; then
            return 1
        fi
    done

    return 0
}

# Both exceptions obey one rule: after substituting the real common directory,
# the lexical root must already be its real path and a strict descendant of it.
# Thus a symlink at the root or anywhere below common grants no allowance.
usable_exception_root() {
    local lexical_root="$1" resolved="$2" candidate
    check_git_invariant "$lexical_root" "$common_lexical" || return 1
    [[ "$lexical_root" != "$common_lexical" ]] || return 1
    candidate="$common_dir${lexical_root#"$common_lexical"}"
    [[ "$resolved" == "$candidate" && "$resolved" != "$common_dir" ]] || return 1
    check_git_invariant "$resolved" "$common_dir" || return 1
    printf '%s\n' "$resolved"
}

if is_git_path "$file_path" || is_git_path "$resolved_path"; then
    nearest_target="$file_path"
    case "$nearest_target" in
    /*) ;;
    *) nearest_target="${CLAUDE_PROJECT_DIR:-$PWD}/$nearest_target" ;;
    esac

    nearest_dir="$(dirname -- "$nearest_target")"
    while [[ ! -d "$nearest_dir" && "$nearest_dir" != "/" && "$nearest_dir" != "." ]]; do
        nearest_dir="$(dirname -- "$nearest_dir")"
    done

    common_dir=""
    if [[ -d "$nearest_dir" ]]; then
        common_dir="$(git -C "$nearest_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null && printf '.')" || true
        common_dir="${common_dir%$'\n.'}"
    fi

    if [[ -z "$common_dir" ]]; then
        nearest_res="$(dirname -- "$resolved_path")"
        while [[ ! -d "$nearest_res" && "$nearest_res" != "/" && "$nearest_res" != "." ]]; do
            nearest_res="$(dirname -- "$nearest_res")"
        done
        if [[ -d "$nearest_res" ]]; then
            common_dir="$(git -C "$nearest_res" rev-parse --path-format=absolute --git-common-dir 2>/dev/null && printf '.')" || true
            common_dir="${common_dir%$'\n.'}"
            nearest_dir="$nearest_res"
        fi
    fi

    if [[ -z "$common_dir" ]]; then
        echo "protect-files: blocked write to '$file_path' (git internal path)" >&2
        exit 2
    fi

    case "$common_dir" in
    /*) ;;
    *) common_dir="$nearest_dir/$common_dir" ;;
    esac

    sidecar_root="$(git -C "$nearest_dir" rev-parse --path-format=absolute --git-path deferred-findings 2>/dev/null && printf '.')" || sidecar_root=""
    sidecar_root="${sidecar_root%$'\n.'}"
    # Absolute formatting resolves root symlinks, so also ask Git for its
    # unformatted lexical path to prove that no exception-root alias was hidden.
    sidecar_lexical="$(git -C "$nearest_dir" rev-parse --git-path deferred-findings 2>/dev/null && printf '.')" || sidecar_lexical=""
    sidecar_lexical="${sidecar_lexical%$'\n.'}"
    if [[ -n "$sidecar_lexical" ]]; then
        case "$sidecar_lexical" in
        /*) ;;
        *) sidecar_lexical="$nearest_dir/$sidecar_lexical" ;;
        esac
    fi
    refuse_control_paths "$common_dir" "$sidecar_root" "$sidecar_lexical"
    common_lexical="$common_dir"

    common_dir="$(normalize_path "$common_dir" && printf '.')" || common_dir=""
    common_dir="${common_dir%$'\n.'}"
    refuse_control_paths "$common_dir"

    if [[ -z "$common_dir" || ! -d "$common_dir" ]]; then
        echo "protect-files: blocked write to '$file_path' (git internal path)" >&2
        exit 2
    fi

    if [[ -z "$sidecar_root" || -z "$sidecar_lexical" ]]; then
        echo "protect-files: blocked write to '$file_path' (git internal path)" >&2
        exit 2
    fi
    dev_flow_resolved="$(normalize_path "$common_dir/dev-flow-v2" && printf '.')" || dev_flow_resolved=""
    dev_flow_resolved="${dev_flow_resolved%$'\n.'}"
    refuse_control_paths "$dev_flow_resolved"
    dev_flow_root="$(usable_exception_root "$common_lexical/dev-flow-v2" "$dev_flow_resolved")" || dev_flow_root=""
    sidecar_root="$(usable_exception_root "$sidecar_lexical" "$sidecar_root")" || sidecar_root=""

    if ! { [[ -n "$dev_flow_root" ]] && check_git_invariant "$resolved_path" "$dev_flow_root"; } &&
        ! { [[ -n "$sidecar_root" ]] && check_git_invariant "$resolved_path" "$sidecar_root"; }; then
        echo "protect-files: blocked write to '$file_path' (git internal path)" >&2
        exit 2
    fi
fi

# Suffix and glob patterns — sensitive credentials, matched against the
# basename only so a directory merely starting with .env (.environment/,
# .env.d/) does not block every file beneath it. Checked on both the requested
# file path and its resolved target so symlink indirection cannot bypass it.
for candidate in "${file_path##*/}" "${resolved_path##*/}"; do
    case "$candidate" in
    *.pem | *.key | *.env | .env*)
        echo "protect-files: blocked write to '$file_path' (matches protected credential pattern)" >&2
        exit 2
        ;;
    esac
done

exit 0
