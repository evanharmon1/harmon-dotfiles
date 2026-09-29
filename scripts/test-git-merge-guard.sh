#!/usr/bin/env bash
# test-git-merge-guard.sh — table-driven test for private_dot_claude/hooks/executable_git-merge-guard.py.
#
# The guard replaces the `Bash(git merge:*)` permissions.ask rules, so a
# regression here silently removes the merge-into-main backstop. Every case
# feeds a real PreToolUse payload to the hook and checks its decision against
# throwaway repos: a feature-branch worktree, the default branch, a detached
# HEAD, a repo whose default branch is `trunk`, and one with no resolvable
# remote HEAD. A final pass runs a deliberately broken copy of the guard (one
# that never asks about the target branch) and requires the matrix to catch
# it, so the suite cannot pass vacuously.
# Run via `task test:hooks`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="${GUARD:-${repo_root}/private_dot_claude/hooks/executable_git-merge-guard.py}"

# Fixture commits must not trip a global signing config or core.hooksPath.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture() { # dir default-branch feature-branch set-remote-head(yes|no) [remote-name]
    local rem=${5:-origin}
    git init -q -b "$2" "$1"
    git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'chore: fixture'
    git -C "$1" branch "$3"
    git -C "$1" remote add "$rem" "${tmp}/absent.git"
    git -C "$1" update-ref "refs/remotes/${rem}/$2" HEAD
    if [[ $4 == yes ]]; then
        git -C "$1" symbolic-ref "refs/remotes/${rem}/HEAD" "refs/remotes/${rem}/$2"
    fi
}
r="${tmp}/repo"
fixture "$r" main feat yes
git -C "$r" worktree add -q "${r}/wt" feat
git -C "$r" worktree add -q --detach "${r}/det" main
tr="${tmp}/trunk"
fixture "$tr" trunk feat yes
git -C "$tr" worktree add -q "${tr}/wt" feat
nh="${tmp}/nohead"
fixture "$nh" trunk feat no
git -C "$nh" worktree add -q "${nh}/wt" feat
sl="${tmp}/slashed"
fixture "$sl" trunk feat yes team/origin
git -C "$sl" worktree add -q "${sl}/wt" feat
# Tags named like branches make `symbolic-ref --short` print `heads/<name>`.
am="${tmp}/ambiguous"
fixture "$am" main feat yes
git -C "$am" tag main
git -C "$am" tag feat
git -C "$am" worktree add -q "${am}/wt" feat 2>/dev/null # expected: "refname is ambiguous"

failures=0
decide() { # guard cwd command -> silent|ask|rc<N>
    local out rc
    out="$(jq -nc --arg c "$3" --arg d "$2" \
        '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | python3 "$1")" && rc=0 || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "rc${rc}"
    elif [[ -z $out ]]; then
        echo silent
    elif jq -e '.hookSpecificOutput.permissionDecision == "ask"
        and (.hookSpecificOutput.permissionDecisionReason | length > 0)' <<<"$out" >/dev/null; then
        echo ask
    else
        echo "unexpected:${out}"
    fi
}
case_() { # guard expected cwd command
    local got
    got="$(decide "$1" "$3" "$4")"
    if [[ $got != "$2" ]]; then
        failures=$((failures + 1))
        [[ ${QUIET:-0} == 1 ]] || echo "  FAIL expected=$2 got=${got} :: [${3#"$tmp"/}] $4" >&2
    fi
}
nl=$'\n'
matrix() { # guard
    local g=$1
    # Allowlisted merges into a verified feature branch: no opinion.
    case_ "$g" silent "${r}/wt" "git merge origin/main --no-edit"
    case_ "$g" silent "${r}/wt" "git merge --no-ff main"
    case_ "$g" silent "${r}/wt" "git merge --abort"
    case_ "$g" silent "${r}/wt" "git pull --ff-only"
    case_ "$g" silent "${r}/wt" "git pull origin main --no-edit"
    case_ "$g" silent "${tr}/wt" "git merge trunk --no-edit"
    case_ "$g" silent "${sl}/wt" "git merge trunk --no-edit"
    case_ "$g" silent "${am}/wt" "git merge main --no-edit"
    # Merges that land on main or the remote default, or an unverifiable target.
    case_ "$g" ask "$r" "git merge feat"
    case_ "$g" ask "$r" "git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "cd ${r} && git merge feat"
    case_ "$g" ask "${r}/det" "git merge feat"
    case_ "$g" ask "$r" "git pull"
    case_ "$g" ask "$tr" "git merge feat"
    case_ "$g" ask "${nh}/wt" "git merge trunk"
    case_ "$g" ask "$sl" "git merge feat"
    case_ "$g" ask "$am" "git merge feat"
    case_ "$g" ask "$r" "cd wt && git merge main"
    case_ "$g" ask "${tmp}/missing" "git merge main"
    # Shapes the guard does not allowlist: always ask.
    # cd / -C paths: the silent path takes no path arguments at all, so a
    # symlink-then-.. or quoted-~ path can't make the guard verify a
    # different checkout than the one git uses (review round 1).
    case_ "$g" ask "$r" "cd ${r}/wt && git merge origin/main --no-edit"
    case_ "$g" ask "$r" "cd ./wt && git merge main"
    case_ "$g" ask "$r" "git -C ${r}/wt merge --no-ff main"
    case_ "$g" ask "${r}/wt" "git -C ./hop/.. merge main"
    case_ "$g" ask "${r}/wt" "git -C \"~/repo\" merge main"
    # Quote-synthesized words on a FEATURE checkout must still ask.
    case_ "$g" ask "${r}/wt" "g''it merge main"
    case_ "$g" ask "${r}/wt" "git mer''ge main"
    case_ "$g" ask "${r}/wt" "git merge 'main'"
    case_ "$g" ask "relative/wt" "git merge main"
    case_ "$g" ask "${r}/wt" "git checkout main && git merge feat"
    case_ "$g" ask "${r}/wt" "git merge main; git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "git status; git merge main"
    case_ "$g" ask "$r" "git status${nl}git merge feat"
    case_ "$g" ask "$r" "cd wt${nl}git merge main"
    case_ "$g" ask "$r" "if git merge feat; then echo ok; fi"
    case_ "$g" ask "$r" "command git merge feat"
    case_ "$g" ask "$r" "g''it merge feat"
    case_ "$g" ask "$r" "git mer''ge feat"
    case_ "$g" ask "$r" "GIT merge feat"
    case_ "$g" ask "$r" "G=git; \$G merge feat"
    case_ "$g" ask "${r}/wt" "git merge main || true"
    case_ "$g" ask "${r}/wt" "git merge \$(echo main)"
    case_ "$g" ask "${r}/wt" "git merge main > /dev/null"
    case_ "$g" ask "${r}/wt" "FOO=1 git merge main"
    case_ "$g" ask "${r}/wt" "git -c core.hooksPath=/dev/null merge main"
    case_ "$g" ask "${r}/wt" "git merge -s ours main"
    case_ "$g" ask "${r}/wt" "git merge main feat"
    case_ "$g" ask "${r}/wt" "bash -c 'git merge main'"
    case_ "$g" ask "${r}/wt" "/usr/bin/git merge main && echo ok"
    case_ "$g" ask "${r}/wt" "true; gh pr view 1; git merge main"
    case_ "$g" ask "${r}/wt" "git merge 'unbalanced"
    case_ "$g" ask "$r" "git \$'\\x6d\\x65\\x72\\x67\\x65' feat"
    case_ "$g" ask "$r" "git mer\\${nl}ge feat"
    case_ "$g" ask "$r" "git m*rge feat"
    case_ "$g" ask "$r" "git \"\$SUB\" feat"
    # No git merge/pull: no opinion, including everyday near-misses.
    case_ "$g" silent "${r}/wt" "git merge-base main feat"
    case_ "$g" silent "${r}/wt" "git log --merges --oneline"
    case_ "$g" silent "${r}/wt" "git commit -m 'fix: catch-up merge of main'"
    case_ "$g" silent "${r}/wt" "git status && git log -1"
    case_ "$g" silent "${r}/wt" "gh pr merge 1"
    case_ "$g" silent "${r}/wt" "gh pr view \"\$N\" --json mergeStateStatus,mergedAt"
    case_ "$g" silent "${r}/wt" "grep -rn merge docs/"
    case_ "$g" silent "${r}/wt" "ls pull-requests/"
    case_ "$g" silent "${r}/wt" "git -C \"\$HOME\" status"
    case_ "$g" silent "${r}/wt" "git log -- '*.md'"
    case_ "$g" silent "${r}/wt" "git log --format='%h %s' -1"
    case_ "$g" silent "${r}/wt" "cat > body.md <<'EOF'${nl}this pull request adds a guard${nl}EOF"
}

echo "==> git-merge-guard decision matrix"
matrix "$guard"
if [[ $failures -ne 0 ]]; then
    echo "TEST FAIL: git-merge-guard: ${failures} case(s) wrong" >&2
    exit 1
fi

echo "==> git-merge-guard matrix catches a guard that never checks the target branch"
mutant="${tmp}/mutant.py"
sed 's/^    if feature_branch(target) is None:$/    if False:/' "$guard" >"$mutant"
if cmp -s "$guard" "$mutant"; then
    echo "TEST FAIL: mutation did not apply (feature_branch check line changed?)" >&2
    exit 1
fi
QUIET=1 matrix "$mutant"
if [[ $failures -eq 0 ]]; then
    echo "TEST FAIL: matrix passed a guard that allows merges into main" >&2
    exit 1
fi

echo "==> git-merge-guard OK"
