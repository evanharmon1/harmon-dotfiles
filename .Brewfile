# Repo toolchain Brewfile for Harmon Dotfiles (kept as `.Brewfile`)
# Install with: task install  (brew bundle --file=.Brewfile)
#
# This is the REPO's own toolchain — the tools the Taskfile, lefthook hooks, and
# scripts/ invoke to lint/verify this repo. It is deliberately separate from
# `private_Brewfile`, which chezmoi deploys to ~/Brewfile (your full dev-machine
# package set). This file is named `.Brewfile` because chezmoi never treats a
# source file starting with `.` as a target, so it is never deployed. It must NOT
# be named `Brewfile`: that is the target name of `private_Brewfile`, and chezmoi
# cannot ignore one source while deploying another that resolves to the same
# target path (#117). `brew bundle` needs an explicit `--file=.Brewfile`.
#
# Base-OS prerequisite, deliberately not a brew entry: `file(1)`, which
# scripts/lint-hygiene.sh requires. macOS ships /usr/bin/file and every
# mainstream Linux distro installs it in the base system, so a brew formula
# would shadow the system binary to no benefit. CI provisions it explicitly via
# scripts/ensure-file.sh; if it is somehow absent locally, lint-hygiene.sh says
# so by name and exits rather than misreporting binaries as text.

# Task runner + git hooks
brew "go-task"
brew "lefthook"

# Git / GitHub
brew "git"
brew "gh"
brew "git-delta"

# Lint / format
brew "shellcheck"
brew "shfmt"
brew "actionlint"
brew "yamllint"

# Security
brew "gitleaks"

# Runtime for npx-based tools (commitlint, markdownlint-cli2)
brew "node"
# Python tool runner (Semgrep CE use uv/uvx)
brew "uv"
# Repository scripts (status, secret helpers) parse JSON with bare `python3`.
# Stock macOS ships 3.9 and uv provides no `python3` shim, so the interpreter
# itself is still a dependency.
brew "python"

# Skills sync (scripts/sync-skills.sh reads .skills-sync.yaml)
brew "yq"

# Utilities
# coreutils provides `timeout`, which stock macOS lacks — scripts/status.sh
# bounds its network probes with it.
brew "coreutils"
brew "direnv"
brew "jq"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "bat"
brew "tokei"
brew "gum"          # status dashboard rendering (scripts/status.sh)
brew "television"   # interactive task menu (`task` / task menu-tv → tv)
