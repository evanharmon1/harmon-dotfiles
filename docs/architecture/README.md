# Architecture

How the system is built, secured, governed, and tested — plus the **subject
hubs** below.

TODO: Describe the high-level architecture of Harmon Dotfiles.

## Overview

TODO: Add a Mermaid diagram of the main components and data flow. Keep this
diagram in sync with reality — PRs that change components, routing, or
infrastructure should update it.

```mermaid
flowchart LR
    A[TODO: source] --> B[TODO: build] --> C[TODO: deploy]
```

## Components

TODO: List the major components and what each is responsible for.

## Data Flow

TODO: Describe how data moves through the system.

## Chezmoi run scripts

`.chezmoiscripts/` holds scripts chezmoi **runs** during `chezmoi apply` without
deploying them into `$HOME` — the place for state that has to be *asserted*
rather than owned as a file.

- `run_after_configure-claude-remote-control.sh` — merges
  `"remoteControlAtStartup": true` into `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`
  with `jq`, so local `claude` sessions register with claude.ai/code on startup
  (issue #67). It mirrors the equivalent block in harmon-init's
  `.devcontainer/scripts/post-start-common.sh`.

  `~/.claude.json` is **not** chezmoi-managed: it is Claude Code's own runtime
  state (startup counters, per-project history, OAuth bookkeeping) and is
  rewritten constantly, so a managed file would clobber it on every apply. The
  script therefore edits one key in place — atomically, preserving the file's
  mode — and is idempotent: an already-true file is left byte-identical and
  prints nothing. Every failure path (no `jq`, invalid JSON, a failed edit)
  warns to stderr and exits 0, so it can never fail an apply. It uses
  `run_after_` rather than `run_onchange_` because the invariant is "every
  apply re-asserts the key" — Claude Code can flip the value back at any time.
  Covered by `task test:claude-config`.

## Subject hubs

Each synthesizes what's scattered across config, settings, and state, then routes
onward (diagrams and component deep-dives also live here):

- [ci-cd.md](ci-cd.md) — the pipeline across YAML, runners, and deploy platforms; routes to the release decision and the deploy guide.
- [security.md](security.md) — the posture across config, secret state, and GitHub settings; holds the threat-model framing, not the config.
- [branch-protection.md](branch-protection.md) — in-repo (CODEOWNERS) + out-of-repo (ruleset, Actions toggles, bot model) stitched into one picture (grep can't see GitHub settings).
- [tests.md](tests.md) — the testing strategy holistically (shape, layers, what's tested where); routes to the testing decision and the guides.
