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
   `git merge`/`git pull` it cannot verify lands on a feature branch — on the
   host and in the dev devcontainer; the bot and agent profiles rely on the
   "Protect Main" ruleset instead.)

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

**Run every real merge as its own visible command.** Not a rule: a
convention that keeps the merge guard useful. The `git-merge-guard` hook
(rule 1) parses each Bash command and asks only on a real or possible
`git merge`/`git pull`; quoted text, heredoc bodies no shell runs, search
patterns and `git merge-base` are data, so prose and flags that merely name the words need
no workaround (the docstring of `~/.claude/hooks/git-merge-guard.py` lists
what it matches). Run every `git merge` or `git pull` as its own plain
command, never hidden in a script, an alias or an evaluated string, and never
reworded to keep the guard silent (rules 1 and 2). The hook reads each whole
command, so a `git merge`/`git pull` in a compound command still asks, and
so does a command it cannot parse that mentions merge or pull.
