#!/usr/bin/env python3
"""PreToolUse(Bash) hook: ask before any git merge/pull that is not a
recognized merge into a feature branch.

Replaces the `Bash(git merge)` / `Bash(git merge:*)` permissions.ask rules,
which prompt on every merge (including routine catch-up merges of main into
a lane branch) yet miss `git -C <dir> merge` entirely, because permission
rules match literal command prefixes.

Invariant: the hook returns "ask" for every command that MIGHT run a git
merge or pull, unless the whole command is exactly one allowlisted shape run
in a verified feature-branch checkout. "Might run" is deliberately coarse:

  * after shell unquoting, the command's words include `git` (any case, any
    path) and `merge` or `pull` anywhere (so newlines, `if`, `command`,
    `g''it`, and compound lines are all covered); or
  * the command cannot be tokenized, or uses indirection (`$`, backticks,
    backslashes, eval, xargs, a nested shell), and mentions merge/pull.

The only silent (normal permission flow) shape is

    [cd <dir> &&] git [-C <dir>] merge [--no-edit|--no-ff|--ff|--ff-only] <ref>
    [cd <dir> &&] git [-C <dir>] merge --abort|--continue
    [cd <dir> &&] git [-C <dir>] pull [--ff-only|--no-edit|--no-rebase] [<remote> [<ref>]]

where the target checkout is on a named branch that is not main/master and
differs from every remote's resolved default branch -- at least one remote
default must resolve (`git remote set-head <remote> --auto`), or it asks.

The parser only decides when to stay SILENT; any gap in it costs a prompt,
never a silent merge. (harmon-init's decision to remove guard-process-kill
explains why an open-ended "is this safe?" classifier was rejected.)

Known limits, shared with or no worse than the rules it replaces: it does
not see through git aliases or scripts, and it trusts the local
`refs/remotes/<remote>/HEAD` cache -- after a remote renames its default
branch, run `git remote set-head <remote> --auto` (main/master stay
protected regardless). A
hook "allow" cannot override a permissions.ask rule, so this hook only ever
adds prompts.

Tests: scripts/test-git-merge-guard.sh (run by `task test:hooks`) in
harmon-infra and harmon-dotfiles. Template adoption: evanharmon1/harmon-init#1435.
"""

import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master"}
MERGE_WORDS = {"merge", "pull"}
MERGE_FLAGS = {"--no-edit", "--no-ff", "--ff", "--ff-only"}
PULL_FLAGS = {"--ff-only", "--no-edit", "--no-rebase"}
SOLO_FLAGS = {"--abort", "--continue"}
REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
PATH = re.compile(r"^[A-Za-z0-9._/~+-]+$")
MENTION = re.compile(r"\b(?:merge|pull)\b", re.I)
INDIRECTION = re.compile(r"[$`\\]|\beval\b|\bxargs\b|\b(?:ba|z|da|k|c)?sh\b")


def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    return list(lexer)


def might_merge(command):
    """True when the command could run a git merge/pull (coarse on purpose)."""
    try:
        tokens = tokenize(command)
    except ValueError:  # unbalanced quotes, e.g. an apostrophe in a heredoc
        return bool(MENTION.search(command))
    words = {os.path.basename(t).lower() for t in tokens}
    if "git" in words and words & MERGE_WORDS:
        return True
    return bool(INDIRECTION.search(command) and MENTION.search(command))


def allowlisted_target(command, cwd):
    """Return the checkout dir if the command is exactly the silent shape."""
    if INDIRECTION.search(command) or "\n" in command:
        return None
    tokens = tokenize(command)
    if "&&" in tokens:
        split = tokens.index("&&")
        cd, call = tokens[:split], tokens[split + 1 :]
        if len(cd) != 2 or cd[0] != "cd" or not PATH.match(cd[1]):
            return None
        if not cd[1].startswith(("/", "./", "../", "~/")):
            return None  # a bare `cd wt` can resolve through CDPATH elsewhere
        cwd = os.path.join(cwd, os.path.expanduser(cd[1]))
    else:
        call = tokens
    if any(set(t) <= set(";&|<>()") for t in call) or call[:1] != ["git"]:
        return None
    args = call[1:]
    if args[:1] == ["-C"] and len(args) >= 2 and PATH.match(args[1]):
        cwd = os.path.join(cwd, os.path.expanduser(args[1]))
        args = args[2:]
    if not args or args[0] not in MERGE_WORDS:
        return None
    sub, rest = args[0], args[1:]
    refs = [a for a in rest if not a.startswith("-")]
    flags = set(a for a in rest if a.startswith("-"))
    if not all(REF.match(r) for r in refs):
        return None
    if sub == "merge":
        ok = (len(rest) == 1 and rest[0] in SOLO_FLAGS) or (
            len(refs) == 1 and flags <= MERGE_FLAGS
        )
    else:
        ok = len(refs) <= 2 and flags <= PULL_FLAGS
    return os.path.normpath(cwd) if ok else None


def git(cwd, *args):
    out = subprocess.run(
        ["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5
    )
    return out.stdout.strip() if out.returncode == 0 else None


def feature_branch(cwd):
    """Return the branch if cwd is provably on a non-default named branch."""
    if not os.path.isdir(cwd):
        return None
    branch = git(cwd, "symbolic-ref", "--quiet", "--short", "HEAD")
    if not branch or branch in PROTECTED:
        return None
    defaults = set()
    for remote in (git(cwd, "remote") or "").split():
        ref = git(
            cwd, "symbolic-ref", "--quiet", "--short", f"refs/remotes/{remote}/HEAD"
        )
        if ref and ref.startswith(remote + "/"):
            defaults.add(ref[len(remote) + 1 :])
    if not defaults or branch in defaults:
        return None
    return branch


def decide(command, cwd):
    """Return None (no opinion) or the reason to ask."""
    if not might_merge(command):
        return None
    target = allowlisted_target(command, cwd)
    if target is None:
        return "git merge/pull in a form this guard does not allowlist"
    if feature_branch(target) is None:
        return (
            "git merge/pull would land on main/master or the remote default "
            "branch, or the target branch could not be verified "
            f"(detached HEAD, no resolvable remote HEAD, unreadable): {target}"
        )
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command", "")
        if payload.get("tool_name") != "Bash" or not command:
            return
        reason = decide(command, payload.get("cwd") or os.getcwd())
    except Exception as exc:  # fail closed
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
