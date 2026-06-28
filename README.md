# Harmon Dotfiles

My dotfiles (.zshrc, .gitconfig, terminal config, ghostty, starship, etc.) managed with Chezmoi

[Harmon Dotfiles](https://github.com/evanharmon1/harmon-dotfiles)

Author: Evan Harmon

[![Build](https://github.com/evanharmon1/harmon-dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/evanharmon1/harmon-dotfiles/actions/workflows/build.yml)
[![Copier](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/copier-org/copier/master/img/badge/badge-grayscale-inverted-border-orange.json)](https://github.com/copier-org/copier)
[![Maintained](https://img.shields.io/badge/maintained%3F-yes-brightgreen.svg?style=flat-square)](https://github.com/evanharmon1/harmon-dotfiles)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat-square)](https://github.com/evanharmon1/harmon-dotfiles)
[![Known Vulnerabilities](https://snyk.io/test/github/evanharmon1/harmon-dotfiles/badge.svg?style=flat-square)](https://snyk.io/test/github/evanharmon1/harmon-dotfiles)

## Part of harmon-stack

This repo is part of **harmon-stack** — my personal stack of homelab, dev-tooling, and automation repos that work together.

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

TODO: project usage

### Task Runner

[Taskfile.yml](./Taskfile.yml)

### Verify

`task verify` runs the fast local gate (lint + Taskfile/hook guards); `task ci`
mirrors the full pipeline.

#### Security

`task security` — gitleaks secret scan + dependency audit.

#### Linting, formatting & conventions

Git hooks (managed by [lefthook](https://lefthook.dev/), `lefthook.yml`) and CI
delegate to the same Taskfile targets. Config lives in `.editorconfig`,
`.shellcheckrc`, `.yamllint`, `.markdownlint.json`, `commitlint.config.mjs`, and
`.gitleaks.toml`.

### Building, Deploying, & CI/CD

## Todo File

[todo.md](./todo.md)
