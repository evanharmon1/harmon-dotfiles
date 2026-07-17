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
| [harmon-ops](https://github.com/evanharmon1/harmon-ops) | Personal machine bootstrapping, package management & dev-environment setup across macOS/Windows/Linux. |
| [harmon-infra](https://github.com/harmonops/harmon-infra) | Homelab infrastructure as code — Terraform, Ansible, and Docker Compose services. |

## Setup & Installation

### Requirements

- Homebrew
- [chezmoi](https://www.chezmoi.io/) (applies the dotfiles to your home directory)
- [Taskfile](https://taskfile.dev/) (task runner)

### Bootstrap

Install required software to run other project installers and task runners
`task bootstrap`

### Install

Install required dependencies
`task install`

## Usage

This repository is the chezmoi source of truth. Edit a managed file through
`chezmoi edit <target>` or edit its corresponding source file here, inspect the
result with `chezmoi diff`, then apply it with `chezmoi apply`. Use `chezmoi
re-add <target>` only for non-template files; live edits to `*.tmpl` targets are
not recoverable with `re-add`.

Run `task test` to render the entire source against an isolated temporary home
with `chezmoi apply --dry-run`. It does not modify the real home directory or
refresh externals.

### Task Runner

[Taskfile.yml](./Taskfile.yml)

### Verify

`task check` runs the fast lint gate. `task verify` is the definition-of-done
gate (check + validation + Taskfile guards + tests); `task ci` adds security.

#### Security

`task security` — Semgrep CE SAST + gitleaks secret scan + dependency audit. Optional Snyk second-opinion targets remain manual/local.

#### Linting, formatting & conventions

Git hooks (managed by [lefthook](https://lefthook.dev/), `lefthook.yml`) and CI
delegate to the same Taskfile targets. Config lives in `.editorconfig`,
`.shellcheckrc`, `.yamllint`, `.markdownlint.json`, `commitlint.config.mjs`, and
`.gitleaks.toml`.
