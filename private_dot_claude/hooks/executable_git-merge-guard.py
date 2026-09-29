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
  * a git call's subcommand word is not a literal (an expansion, quote,
    escape or glob such as `git $'\x6d...'` or `git m*rge`); or
  * the command cannot be tokenized, or uses indirection (`$`, backticks,
    backslashes, eval, xargs, a nested shell), and mentions merge/pull.

The only silent (normal permission flow) shape is one fully literal command
-- no quotes, escapes, expansions, globs, operators, newlines, `cd` or `-C`:

    git merge [--no-edit|--no-ff|--ff|--ff-only] <ref>
    git merge --continue
    git pull [--ff-only|--no-edit|--no-rebase] [<remote> [<ref>]]

run in the working directory Claude Code reports in the hook payload (a lane
merges from its own worktree), where that checkout is on a named branch that
is not main/master and
differs from every remote's resolved default branch -- at least one remote
default must resolve (`git remote set-head <remote> --auto`), or it asks.

The parser only decides when to stay SILENT; any gap in it costs a prompt,
never a silent merge. (harmon-init's decision to remove guard-process-kill
explains why an open-ended "is this safe?" classifier was rejected.)

Known limits, shared with or no worse than the rules it replaces: it does
not see through git aliases, scripts, or shell functions and aliases from the
user's profile -- including ones this repo ships (`gitum` checks out main and
pulls; the `ghpprm` alias runs `gh pr merge --auto`; `gitsend` pushes the
current branch) -- nor through deliberate obfuscation
that hides both the `git` word and the subcommand (e.g. both in variables);
it is a backstop against mistakes, not an adversarial boundary.
It gates only git merge/pull: `git reset --hard`, `git restore` and
`git checkout -- .` discard the same conflict resolutions `git merge --abort`
would, and this hook does not see them. `git pull --rebase` is not silent,
because it can rewrite already-pushed feature-branch commits. In unattended
runs (`claude -p`, lanes) an "ask" is effectively a denial, so a conflicted
merge there is recovered by a human, not by the agent. It trusts the local
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
# `--abort` is deliberately absent: it resets the index and worktree and can
# discard in-progress conflict resolutions (same class as `git reset --hard`).
SOLO_FLAGS = {"--continue"}
REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
LITERAL_UNSAFE = re.compile(r"[\"'`$\\\n;&|<>(){}*?\[\]~]")
MENTION = re.compile(r"\b(?:merge|pull)\b", re.I)
INDIRECTION = re.compile(r"[$`\\]|\beval\b|\bxargs\b|\b(?:ba|z|da|k|c)?sh\b")
EXPANSION = re.compile(r"[$`\\*?\[{'\"]")
GIT_VALUE_OPTIONS = ("-C", "-c", "--git-dir", "--work-tree", "--namespace")


def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    return list(lexer)


def git_subcommand_not_literal(command):
    """True when some git call's subcommand word is shell-synthesized.

    Scans raw (still-quoted) tokens: a subcommand slot holding an
    expansion, quote, escape or glob could become `merge` at run time.
    """
    lexer = shlex.shlex(command, posix=False, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    try:
        raw = list(lexer)
    except ValueError:
        return bool(MENTION.search(command))
    for i, tok in enumerate(raw):
        if os.path.basename(re.sub(r"[\"'\\]", "", tok)).lower() != "git":
            continue
        j = i + 1
        while j < len(raw) and raw[j].startswith("-"):
            j += 2 if raw[j] in GIT_VALUE_OPTIONS else 1
        if j < len(raw) and EXPANSION.search(raw[j]):
            return True
    return False


def might_merge(command):
    """True when the command could run a git merge/pull (coarse on purpose)."""
    try:
        tokens = tokenize(command)
    except ValueError:  # unbalanced quotes, e.g. an apostrophe in a heredoc
        return bool(MENTION.search(command))
    words = {os.path.basename(t).lower() for t in tokens}
    if "git" in words and (words & MERGE_WORDS or git_subcommand_not_literal(command)):
        return True
    return bool(INDIRECTION.search(command) and MENTION.search(command))


def allowlisted_target(command, cwd):
    """Return cwd if the whole command is exactly the silent shape.

    The shape is one fully literal `git merge` / `git pull` with no path
    arguments: no quotes, escapes, expansions, globs, operators or newlines,
    and no `cd` / `-C`. The checkout the guard verifies is therefore the one
    git will use -- the working directory Claude Code reports in the payload.
    """
    if LITERAL_UNSAFE.search(command) or not os.path.isabs(cwd):
        return None
    tokens = command.split()
    if len(tokens) < 2 or tokens[0] != "git" or tokens[1] not in MERGE_WORDS:
        return None
    sub, rest = tokens[1], tokens[2:]
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
    return cwd if ok else None


def git(cwd, *args):
    out = subprocess.run(
        ["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5
    )
    return out.stdout.strip() if out.returncode == 0 else None


def feature_branch(cwd):
    """Return the branch if cwd is provably on a non-default named branch.

    Compares full ref names, never `--short` output: git abbreviates
    ambiguously named refs (a tag `main` makes `refs/heads/main` print as
    `heads/main`), which would slip past a short-name comparison.
    """
    if not os.path.isdir(cwd):
        return None
    head = git(cwd, "symbolic-ref", "--quiet", "HEAD")
    if not head or not head.startswith("refs/heads/"):
        return None
    branch = head[len("refs/heads/") :]
    # refs are files on a case-insensitive filesystem (macOS APFS), so
    # `Main` is `main`: compare casefolded names.
    if branch.casefold() in PROTECTED:
        return None
    defaults = set()
    for remote in (git(cwd, "remote") or "").split():
        prefix = f"refs/remotes/{remote}/"
        ref = git(cwd, "symbolic-ref", "--quiet", f"{prefix}HEAD")
        if ref and ref.startswith(prefix):
            defaults.add(ref[len(prefix) :])
    if not defaults or branch.casefold() in {d.casefold() for d in defaults}:
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
