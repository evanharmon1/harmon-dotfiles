#!/usr/bin/env bash
# test-git-merge-guard.sh — table-driven test for private_dot_claude/hooks/executable_git-merge-guard.py.
#
# The guard replaces the `Bash(git merge:*)` permissions.ask rules, so a
# regression here silently removes the merge-into-main backstop. Every case
# feeds a real PreToolUse payload to the hook and checks its decision against
# throwaway repos: a feature-branch worktree, the default branch, and a
# detached HEAD. A final pass runs a deliberately broken copy of the guard (one
# that treats `main` as a feature branch) and requires the matrix to catch it,
# so the suite cannot pass vacuously.
# Run via `task test:hooks`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="${repo_root}/private_dot_claude/hooks/executable_git-merge-guard.py"

# Fixture commits must not trip a global signing config or core.hooksPath.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
r="${tmp}/repo"
git init -q -b main "$r"
git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'chore: fixture'
git -C "$r" branch feat
git -C "$r" worktree add -q "${r}/wt" feat
git -C "$r" worktree add -q --detach "${r}/det" main

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
matrix() { # guard
    local g=$1
    # Recognized merges into a feature branch: no opinion (normal flow).
    case_ "$g" silent "${r}/wt" "git merge origin/main --no-edit"
    case_ "$g" silent "$r" "cd ${r}/wt && git merge origin/main --no-edit"
    case_ "$g" silent "$r" "cd wt && git merge main"
    case_ "$g" silent "$r" "git -C ${r}/wt merge --no-ff main"
    case_ "$g" silent "${r}/wt" "git merge --abort"
    case_ "$g" silent "${r}/wt" "git pull --ff-only"
    case_ "$g" silent "${r}/wt" "git pull origin main --no-edit"
    # Merges that land on main, a detached HEAD, or an unreadable checkout.
    case_ "$g" ask "$r" "git merge feat"
    case_ "$g" ask "$r" "git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "cd ${r} && git merge feat"
    case_ "$g" ask "${r}/det" "git merge feat"
    case_ "$g" ask "$r" "git pull"
    case_ "$g" ask "${tmp}/missing" "git merge main"
    # Shapes the guard does not recognize: always ask.
    case_ "$g" ask "${r}/wt" "git checkout main && git merge feat"
    case_ "$g" ask "${r}/wt" "git merge main; git -C ${r} merge feat"
    case_ "$g" ask "${r}/wt" "git status; git merge main"
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
    # No git merge/pull invocation: no opinion.
    case_ "$g" silent "${r}/wt" "git merge-base main feat"
    case_ "$g" silent "${r}/wt" "git log --merges --oneline"
    case_ "$g" silent "${r}/wt" "git commit -m 'fix: catch-up merge of main'"
    case_ "$g" silent "${r}/wt" "git status && git log -1"
    case_ "$g" silent "${r}/wt" "gh pr merge 1"
    case_ "$g" silent "${r}/wt" "grep -rn merge docs/"
    case_ "$g" silent "${r}/wt" "ls pull-requests/"
}

echo "==> git-merge-guard decision matrix"
matrix "$guard"
if [[ $failures -ne 0 ]]; then
    echo "TEST FAIL: git-merge-guard: ${failures} case(s) wrong" >&2
    exit 1
fi

echo "==> git-merge-guard matrix catches a guard that treats main as a feature branch"
mutant="${tmp}/mutant.py"
sed 's/^PROTECTED = {"main", "master"}$/PROTECTED = set()/' "$guard" >"$mutant"
cmp -s "$guard" "$mutant" && {
    echo "TEST FAIL: mutation did not apply (PROTECTED line changed?)" >&2
    exit 1
}
# The fixture has no origin/HEAD, so dropping PROTECTED really does let main through.
QUIET=1 matrix "$mutant"
if [[ $failures -eq 0 ]]; then
    echo "TEST FAIL: matrix passed a guard that allows merges into main" >&2
    exit 1
fi

echo "==> git-merge-guard OK"
