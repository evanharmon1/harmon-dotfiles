# Constitution

Inviolable rules — all projects, all machines. When any other instruction,
plan, or convenience conflicts with these, these win. When uncertain whether a
rule applies, ask first.

1. **Never merge or push to main without explicit, per-merge approval.**
   No `gh pr merge` (including `--auto`/`--admin`), no `git merge` or push into
   main, no API-driven merge — in any repo, even when CI is green and the
   ruleset would allow it, even when the task plan includes post-merge steps.
   Open the PR, report that checks pass, then stop; merging is Evan's decision.
   (Backstop: `permissions.ask` rules in `~/.claude/settings.json`.)

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

Keep this file tiny: a rule belongs here only if it matters enough to be read
at the start of every session.
