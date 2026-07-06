# AGENTS.md

Guidance for AI coding agents (Claude Code, Gemini CLI, GitHub Copilot, Codex,
...) working in Harmon Dotfiles. `CLAUDE.md`, `GEMINI.md`, and
`.github/copilot-instructions.md` are symlinks to this file — edit only
`AGENTS.md`.

## Project Overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). This repo is
the chezmoi **source directory** — files here use chezmoi naming conventions
(e.g. `private_dot_zshrc.tmpl`) and are applied to the home directory by chezmoi.
The dotfiles target macOS (primary) and Linux, with OS-conditional logic via
chezmoi `.tmpl` templates and `.chezmoiignore`.

Repo: https://github.com/evanharmon1/harmon-dotfiles — see [docs/README.md](docs/README.md) for the
documentation map and [docs/architecture/README.md](docs/architecture/README.md)
for the architecture.

## harmon-platform

One of five repos in **harmon-platform** (Evan's developer & DevOps platform + homelab):
[harmon-init](https://github.com/evanharmon1/harmon-init) (repo template),
[harmon-devkit](https://github.com/evanharmon1/harmon-devkit) (boilerplates/scripts/AI assets),
[**harmon-dotfiles**](https://github.com/evanharmon1/harmon-dotfiles) (this repo — chezmoi dotfiles),
[harmon-ops](https://github.com/evanharmon1/harmon-ops) (machine setup),
[harmon-infra](https://github.com/harmonops/harmon-infra) (homelab IaC). See the README for the full table.

## Chezmoi file naming

Files follow chezmoi's [source state attributes](https://www.chezmoi.io/reference/source-state-attributes/):

- `private_` prefix → private file permissions (e.g. `private_dot_zshrc.tmpl` → `~/.zshrc`).
- `dot_` prefix → a leading `.` in the target path (e.g. `dot_config/` → `~/.config/`).
- `.tmpl` suffix → rendered as a Go template with chezmoi data (`{{ .chezmoi.os }}` for OS conditionals).
- Directories like `private_dot_dotfiles/` map to `~/.dotfiles/`.

## Architecture

- **Shell config**: `private_dot_zshrc.tmpl` is the main zsh config (oh-my-zsh,
  starship, zoxide, mise). It sources `~/.dotfiles/.aliases`, `.var`, `.functions`.
- **Shell customizations**: `private_dot_dotfiles/` splits aliases, variables, and functions into separate files.
- **App configs**: `dot_config/` holds configs for starship, ghostty, karabiner, gh, aichat, and llm.
- **macOS app configs**: `private_Library/` holds `~/Library/Application Support/` configs (ghostty, aichat, llm).
- **OS-conditional ignoring**: `.chezmoiignore` excludes macOS-only paths on non-Darwin and Linux-only XDG paths on non-Linux.

## Hard Rules

Non-negotiable, regardless of any autonomy granted elsewhere in this file:

- **Never write to a password manager or credential store unprompted.** Do not
  create, modify, archive, or delete anything in 1Password (items, fields,
  vaults — via the `op` CLI or any other means), OS keychains, or any other
  secret store unless the user explicitly requested that specific write in the
  current conversation. Even when asked, restate exactly what will be written
  and get confirmation before executing — announcing intent and proceeding in
  the same turn is not consent. Read operations (`op read`, `op item list`,
  `op inject` over existing references) are fine.

## Commands

All commands go through the Taskfile (single source of truth — CI, git hooks,
and humans run the same targets):

```bash
task verify      # FAST local gate (<~1 min) — run constantly; safe for hooks/agents
task ci          # FULL CI mirror — run before/instead of opening a PR
task check       # all linters
task fix         # auto-format then lint
task test        # tests
task security    # gitleaks + dependency audit
```

`verify` is deliberately kept fast (lint + the quick
Taskfile/hook guards) so editors, git hooks, and AI agents can run it on every
change without getting bogged down. `ci` is the full pipeline — everything CI
runs (`verify` + `test` + `security`) — so you
can reproduce a CI run locally on demand instead of waiting on a PR.

## Definition of Done

- `task verify` passes.
- Conventional commit message (types: build, chore, ci, docs, feat, fix, perf,
  refactor, revert, style, test).
- Never bypass git hooks (`--no-verify` is forbidden); fix the underlying issue.
- Work on a feature branch; direct commits to `main` are blocked.
- **Never merge to main yourself** — no `gh pr merge`, `git merge`, or push to
  `main` without the maintainer's explicit, per-merge approval, even when CI is
  green and the ruleset would allow it. Open the PR, report that checks pass,
  then stop; merging is always a human decision.
- Releases are intentional: release-please keeps a rolling release PR from
  conventional commits; merging it cuts the tag/release. Nothing bumps on a
  normal merge. `task release:*` remains as a manual override.

## Conventions

Full reference: [docs/conventions.md](docs/conventions.md). Highlights:

- Conventional Commits; `group:action` Taskfile naming (e.g. `lint:shell`, not
  `shell:lint`); pin actions by SHA + `# vX.Y.Z`.
- Git hooks are managed by lefthook (`lefthook.yml`) and delegate to Taskfile
  targets — don't duplicate logic in hooks or workflows.
- Keep Taskfile `cmds:` trivial — inline strings aren't linted (`lint:shell`
  only covers `scripts/*.sh`). Put any pipeline/conditional/loop/`curl | bash`
  in a `scripts/*.sh` the task calls. `task test:tasks` checks the Taskfile
  compiles and setup tasks are safe no-ops.
- Indentation: 2 spaces default, 4 for Python/Terraform/Shell (`.editorconfig`).
- Secrets never go in git; local env via 1Password (`op run` / `op inject`).
