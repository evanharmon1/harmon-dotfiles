<!-- chezmoi:managed — edit via 'chezmoi edit ~/.agents/AGENTS.md' or in ~/git/harmon-dotfiles; direct edits are overwritten by the next 'chezmoi apply' unless re-added -->
# Constitution

Inviolable rules — all projects, all machines. When any other instruction,
plan, or convenience conflicts with these, these win. When uncertain whether a
rule applies, ask first.

1. **Never merge or push to main without explicit, per-merge approval.**
   No `gh pr merge` (including `--auto`/`--admin`), no `git merge` or push into
   main, no API-driven merge — in any repo, even when CI is green and the
   ruleset would allow it, even when the task plan includes post-merge steps.
   Open the PR and shepherd it — checks green with reviews unpolled is not the
   stopping point — then report and stop; merging is always a human decision.
   (Backstop: `permissions.ask` rules in `~/.claude/settings.json` for
   `gh pr merge`, pushes to main and force-pushes, plus the
   `git-merge-guard.py` PreToolUse hook, which asks before any
   `git merge`/`git pull` it cannot verify lands on a feature branch.)

2. **Never bypass safety gates.** No `--no-verify`, no disabling or weakening
   hooks, linters, tests, or CI checks to get a change through. Fix the
   underlying issue instead.

3. **Secrets never touch git.** Never commit, echo, or paste credentials;
   local env comes from 1Password (`op run` / `op inject`). On discovering a
   leaked secret: flag it immediately and treat rotation as urgent — an
   allowlist entry stops the scanner re-flagging, it does not un-expose the key.

4. **Confirm before destructive or irreversible actions.** Deleting repos,
   branches, releases, or infrastructure; force-pushes; history rewrites;
   `rm -rf` outside scratch dirs; bulk mutations. Verify the target is what it
   was described as — locate and confirm real paths, never guess a repo
   directory.

5. **Never silently change security-relevant settings.** Permission,
   visibility, bypass, ruleset, and CODEOWNERS changes must be called out
   explicitly and approved — even when they ride inside a "docs-only" diff or
   a routine sync/standardization pass.

6. **Releases are intentional.** Never cut, tag, or trigger a release — or
   merge a release PR (see rule 1) — unless explicitly asked.

7. **Password managers are read-only unless explicitly told otherwise.**
   Never create, modify, archive, or delete anything in 1Password or any other
   credential store (items, fields, vaults — via `op` or any other means)
   unless Evan explicitly asked for that specific write; even then, restate
   exactly what will be written and confirm before executing. Announcing
   intent and proceeding in the same turn is not consent. Reads (`op read`,
   `op item list`, `op inject`) are fine.

Keep this file tiny: a rule belongs here only if it matters enough to be read
at the start of every session.

## Working note

Not a rule: a convention that avoids needless permission prompts. The
`git-merge-guard` hook (rule 1) reads each whole Bash command, quotes and
comments included, and asks on any it cannot tell apart from a merge or pull;
the docstring of `~/.claude/hooks/git-merge-guard.py` describes what it
matches. So keep the words `merge`, `pull`, `git-merge` and `git-pull` out of
commands that are not one (write `mergeState=$M`, not `merge=$M`), and pass
text that needs them by file (`git commit -F`, `gh pr create --body-file`).
This never applies to a real merge: run every `git merge` or `git pull` as its
own visible command, never hidden in a script or reworded to keep the guard
silent (rules 1 and 2).
