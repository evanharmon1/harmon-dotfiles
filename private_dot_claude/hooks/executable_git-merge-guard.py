#!/usr/bin/env python3
"""PreToolUse(Bash) hook: ask before any git merge/pull that is not a
recognized merge into a feature branch.

Replaces the `Bash(git merge)` / `Bash(git merge:*)` permissions.ask rules,
which prompt on every merge (including routine catch-up merges of main into
a lane branch) yet miss `git -C <dir> merge` entirely, because permission
rules match literal command prefixes.

Decision:
  * silent (the normal permission flow applies) for exactly one shape, run
    in a checkout whose current branch is a named branch other than
    main/master and the remote's default branch:

        [cd <dir> &&] git [-C <dir>] merge [--no-edit|--no-ff|--ff|--ff-only] <ref>
        [cd <dir> &&] git [-C <dir>] merge --abort|--continue
        [cd <dir> &&] git [-C <dir>] pull [--ff-only|--no-edit|--no-rebase] [<remote> [<ref>]]

  * "ask" for every other command containing a git merge/pull invocation,
    including ones it cannot parse (substitutions, `bash -c`, `eval`, a
    detached HEAD, an unreadable repo, a hook error).
  * silent for commands that contain no git merge/pull at all.

The hook never classifies arbitrary shell as safe: it recognizes one
allowlisted shape and asks about everything else that mentions a merge. A
parser gap therefore costs a prompt, not a silent merge into main (see
harmon-init docs/decisions/2026-09-02-remove-guard-process-kill-hook.md for
why an open-ended classifier was rejected). Note that a hook "allow" cannot
override a permissions.ask rule, so this hook only ever adds prompts.

Tests: scripts/test-git-merge-guard.sh (run by `task test:hooks`) in harmon-infra and harmon-dotfiles.
Template adoption: evanharmon1/harmon-init#1435.
"""

import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master"}
MERGE_FLAGS = {"--no-edit", "--no-ff", "--ff", "--ff-only"}
PULL_FLAGS = {"--ff-only", "--no-edit", "--no-rebase"}
SOLO_FLAGS = {"--abort", "--continue"}
REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
PATH = re.compile(r"^[A-Za-z0-9._/~+-]+$")
OPERATORS = set(";&|<>()")
INDIRECTION = re.compile(r"\$\(|`|\beval\b|\b(ba|z)?sh\s+-c\b|\bxargs\b")
LOOSE = re.compile(r"\bgit\b.*\b(merge|pull)\b(?![-\w])", re.S)


class Unparsed(Exception):
    pass


def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError as exc:  # unbalanced quotes
        raise Unparsed(str(exc))


def segments(tokens):
    """Split on shell operators; return (segments, operators)."""
    segs, ops, current = [], [], []
    for tok in tokens:
        if tok and set(tok) <= OPERATORS:
            segs.append(current)
            ops.append(tok)
            current = []
        else:
            current.append(tok)
    segs.append(current)
    return segs, ops


def git_subcommand(seg):
    """Return (dir_override, subcommand, args) for a `git ...` segment."""
    i = 0
    while i < len(seg) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]):
        i += 1  # env prefix: still a git call, but never whitelisted
    env = i > 0
    if i >= len(seg) or os.path.basename(seg[i]) != "git":
        return None
    i += 1
    cdir, plain = None, not env
    while i < len(seg) and seg[i].startswith("-"):
        opt = seg[i]
        if opt == "-C" and i + 1 < len(seg):
            cdir = seg[i + 1]
            i += 2
            continue
        plain = False  # -c, --git-dir, --work-tree, ...
        i += 2 if opt in ("-c", "--git-dir", "--work-tree", "--namespace") else 1
    if i >= len(seg):
        return None
    return cdir, seg[i], seg[i + 1 :], plain


def whitelisted_args(sub, args):
    if sub == "merge":
        if len(args) == 1 and args[0] in SOLO_FLAGS:
            return True
        refs = [a for a in args if not a.startswith("-")]
        flags = [a for a in args if a.startswith("-")]
        return len(refs) == 1 and bool(REF.match(refs[0])) and set(flags) <= MERGE_FLAGS
    refs = [a for a in args if not a.startswith("-")]
    flags = [a for a in args if a.startswith("-")]
    return (
        len(refs) <= 2 and all(REF.match(r) for r in refs) and set(flags) <= PULL_FLAGS
    )


def git(cwd, *args):
    out = subprocess.run(
        ["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5
    )
    return out.stdout.strip() if out.returncode == 0 else None


def feature_branch(cwd):
    """Return the branch name if cwd is on a non-protected named branch."""
    if not os.path.isdir(cwd):
        return None
    branch = git(cwd, "symbolic-ref", "--quiet", "--short", "HEAD")
    if not branch or branch in PROTECTED:
        return None
    default = git(cwd, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    if default and branch == default.split("/", 1)[-1]:
        return None
    return branch


def resolve(base, path):
    return os.path.normpath(os.path.join(base, os.path.expanduser(path)))


def decide(command, cwd):
    """Return None (no opinion) or a reason string to ask with."""
    if not LOOSE.search(command):
        return None
    if INDIRECTION.search(command) or "\\" in command:
        return "merge/pull inside a substitution, eval, or nested shell"
    segs, ops = segments(tokenize(command))

    merges = []
    for idx, seg in enumerate(segs):
        call = git_subcommand(seg)
        if call and call[1] in ("merge", "pull"):
            merges.append((idx, call))
    if not merges:
        return None  # "merge" only appeared inside quoted text or as a path
    if len(merges) > 1:
        return "more than one git merge/pull in one command"

    idx, (cdir, sub, args, plain) = merges[0]
    prefix = segs[:idx]
    shape_ok = plain and whitelisted_args(sub, args)
    if prefix:
        cd = prefix[0]
        shape_ok = (
            shape_ok
            and len(prefix) == 1
            and ops[:1] == ["&&"]
            and len(cd) == 2
            and cd[0] == "cd"
            and bool(PATH.match(cd[1]))
        )
        if shape_ok:
            cwd = resolve(cwd, cd[1])
    if len(segs) > idx + 1:
        shape_ok = False  # anything after the merge/pull
    if cdir is not None:
        shape_ok = shape_ok and bool(PATH.match(cdir))
        cwd = resolve(cwd, cdir)

    if not shape_ok:
        return f"git {sub} in a form this guard does not recognize"
    branch = feature_branch(cwd)
    if branch is None:
        return f"git {sub} would land on main/master, the default branch, a detached HEAD, or an unreadable checkout ({cwd})"
    return None


def main():
    payload = json.load(sys.stdin)
    if payload.get("tool_name") != "Bash":
        return
    command = (payload.get("tool_input") or {}).get("command", "")
    try:
        reason = decide(command, payload.get("cwd") or os.getcwd())
    except Exception as exc:  # fail closed on anything that mentions a merge
        reason = f"guard could not analyse the command ({exc.__class__.__name__})"
    if reason:
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": f"git-merge-guard: {reason}",
                }
            },
            sys.stdout,
        )


if __name__ == "__main__":
    main()
