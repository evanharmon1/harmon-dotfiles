# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). This repo is the chezmoi source directory — files here use chezmoi naming conventions (e.g., `private_dot_zshrc.tmpl`) and are applied to the home directory by chezmoi. The dotfiles target macOS (primary) and Linux, with OS-conditional logic via chezmoi `.tmpl` templates and `.chezmoiignore`.

## Key Commands

- **`task validate`** — Run all validation (pre-commit hooks + checks)
- **`task preCommit`** — Run pre-commit hooks on all files (`pre-commit run --all-files`)
- **`task security`** — Run secrets scanning and SAST (whispers + snyk)
- **`task install`** — Install dependencies via Brewfile and pip
- **`task bootstrap`** — Install Homebrew and Python from scratch

## Chezmoi File Naming Conventions

Files follow chezmoi's [source state attributes](https://www.chezmoi.io/reference/source-state-attributes/):
- `private_` prefix → sets file permissions to private (e.g., `private_dot_zshrc.tmpl` → `~/.zshrc`)
- `dot_` prefix → becomes a `.` in the target path (e.g., `dot_config/` → `~/.config/`)
- `.tmpl` suffix → processed as a Go template with chezmoi data (uses `{{ .chezmoi.os }}` for OS conditionals)
- Directories like `private_dot_dotfiles/` map to `~/.dotfiles/`

## Architecture

- **Shell config**: `private_dot_zshrc.tmpl` is the main zsh config (oh-my-zsh, starship, zoxide, pyenv, nvm). It sources `~/.dotfiles/.aliases`, `~/.dotfiles/.var`, and `~/.dotfiles/.functions`.
- **Shell customizations**: `private_dot_dotfiles/` contains aliases, variables, and functions split into separate files
- **App configs**: `dot_config/` holds configs for starship, ghostty, karabiner, gh, aichat, and llm
- **macOS app configs**: `private_Library/` holds configs stored in macOS `~/Library/Application Support/` (ghostty, aichat, llm)
- **OS-conditional ignoring**: `.chezmoiignore` excludes macOS-specific paths (`Library/`, `.mackup*`) on non-Darwin and Linux-specific XDG paths (`.config/ghostty/`, etc.) on non-Linux
- **Brewfile**: `private_Brewfile` is a large Homebrew bundle file for macOS package management

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org): `<type>(scope): description` (e.g., `feat(zsh): add new alias`). Types: feat, fix, chore, docs, style, refactor, perf, test, ci, build, revert.

## Linting & Validation

Pre-commit hooks handle: YAML/JSON/TOML/XML validation, shell linting (shellcheck), Python formatting (black), trailing whitespace, private key detection, and no-commit-to-branch protection. Config files: `.shellcheckrc`, `.yamllint`, `.ansible-lint`, `.markdownlint.json`.

## Project Scaffolding

This repo was scaffolded with [Copier](https://github.com/copier-org/copier) from a `harmon-init` template (see `.copier-answers.yml`). Some Taskfile tasks (check, fix) reference npm scripts from the template that don't apply to this dotfiles repo.
