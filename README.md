# Harmon Dotfiles

My dotfiles (.zshrc, .gitconfig, terminal config, ghostty, starship, etc.) managed with Chezmoi

[Harmon Dotfiles](https://github.com/evanharmon1/harmon-dotfiles)

Author: Evan Harmon

[![Build & Validate](https://github.com/evanharmon1/harmon-dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/evanharmon1/harmon-dotfiles/actions/workflows/build.yml)
[![Latest Release](https://img.shields.io/github/v/release/evanharmon1/harmon-dotfiles?sort=semver)](https://github.com/evanharmon1/harmon-dotfiles/releases)
[![Renovate](https://img.shields.io/badge/maintained%20with-renovate-blue?logo=renovatebot)](https://github.com/apps/renovate)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Copier](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/copier-org/copier/master/img/badge/badge-grayscale-inverted-border-orange.json)](https://github.com/copier-org/copier)
[![Known Vulnerabilities](https://snyk.io/test/github/evanharmon1/harmon-dotfiles/badge.svg?style=flat-square)](https://snyk.io/test/github/evanharmon1/harmon-dotfiles)

## Part of harmon-platform

This repo is part of **harmon-platform** — my custom development platform with machine configuration, DevOps systems, homelab infrastructure, and automation repos that work together to help me develop software and manage my homelab.

| Repo | What it is |
| --- | --- |
| [harmon-init](https://github.com/evanharmon1/harmon-init) | Copier template that bootstraps & standardizes new repos (CI/CD, devcontainers, AI steering, tooling). |
| [harmon-devkit](https://github.com/evanharmon1/harmon-devkit) | Reusable boilerplates & code templates, standalone scripts, and AI assets (skills, prompts, agents). |
| [**harmon-dotfiles**](https://github.com/evanharmon1/harmon-dotfiles) **(this repo)** | Shell & app dotfiles, managed declaratively with chezmoi. |
| [harmon-infra](https://github.com/harmonops/harmon-infra) | Homelab infrastructure as code — Terraform, Ansible, and Docker Compose services. |

## Setup & Installation

### Requirements

- [Homebrew](https://brew.sh/)
- [chezmoi](https://www.chezmoi.io/) (applies the dotfiles to your home directory)
- [go-task](https://taskfile.dev/) (task runner)
- [uv](https://docs.astral.sh/uv/) (runs the pinned Semgrep CE baseline)

### Usage

```bash
task bootstrap   # one-time machine setup (Homebrew)
task install     # Brewfile deps + lefthook git hooks
task verify      # confirm everything passes
```

Or open the repo in the devcontainer (VS Code "Reopen in Container", or a
[Coder](https://coder.com) workspace).

New here? Start with [docs/guides/onboarding.md](docs/guides/onboarding.md) and the
post-generation [docs/CHECKLIST.md](docs/CHECKLIST.md).

## Project Structure

```text
.
├── .claude/             # Claude Code settings + skills
├── .github/             # Workflows, templates, CODEOWNERS, branch ruleset
├── docs/                # Documentation (see docs/README.md)
├── scripts/             # Repo utility scripts (hygiene, status, summaries)
├── specs/               # Specifications
├── tests/               # Tests
├── AGENTS.md            # AI agent guidance (CLAUDE.md/GEMINI.md symlink here)
├── DESIGN.md            # Design / UX intent (AI-facing)
├── Taskfile.yml         # Task runner — single source of truth for commands
├── lefthook.yml         # Git hooks (delegate to Taskfile tasks)
└── todo.md              # Scratch todos (gitignored)
```

## Commands

`task` (or `task menu`) shows the interactive picker. Key targets:

| Command | What it does |
|---|---|
| `task check` | Fast gate: all linters, in parallel |
| `task verify` | Definition-of-done gate: check + validate + tests |
| `task fix` | Auto-format, then lint |
| `task test` | Run tests (see [docs/architecture/tests.md](docs/architecture/tests.md)) |
| `task security` | Free local baseline: Semgrep CE + gitleaks + dependency audit |
| `task security:sast` / `security:sca` | Semgrep CE / package-manager dependency audit |
| `task security:sast:snyk` / `security:sca:snyk` | Optional Snyk second-opinion scans (manual or explicitly scheduled) |
| `task challenge` / `task review` | Codex second-model reviews: adversarial / verification checkpoint (advisory, local-only) |
| `task codex:gate:enable` | Automatic Claude → Codex stop-gate for this repo + machine (also `:disable` / `:status`) |
| `task release:patch` | Tag + GitHub release (also `:minor` / `:major`) |
| `task status` | Project status dashboard (also `status:git`/`:gh`/`:creds`/`:code`/`:env`) |
| `task status:creds` | Credential logins (gh, Codex, Claude Code) + the gh token's scopes — local probes plus one bounded 3s scope check (`STATUS_NO_NETWORK=1` skips it); also run at session start |
| `task status:setup` | Setup audit: local credentials, GitHub config, toolchain, devcontainer, dev env |

## Testing

See [docs/architecture/tests.md](docs/architecture/tests.md). Tests live in `tests/`; CI runs the
same `task` targets as local hooks.

## CI/CD

| Workflow | Purpose |
|---|---|
| `build.yml` | lint, security → aggregate `verify` gate |
| `claude-plan/implement/review.yml` | Mention-only: an `@claude` mention naming `plan`/`implement`/`review` from an authorized sender; each run holds `claim:claude` |
| `release.yml` | release-please maintains a release PR; merging it cuts the release |

Branch protection: `main` requires a PR with code-owner approval and the
`verify` + `security` checks (importable ruleset in `.github/`; see
[docs/architecture/branch-protection.md](docs/architecture/branch-protection.md)).
**Releases are intentional** — release-please keeps a rolling release PR from
conventional commits; merging it cuts the tag, GitHub release, and CHANGELOG.
Nothing auto-releases on a normal merge. `task release:*` stays as a manual
override.

## License

See [LICENSE](LICENSE).
