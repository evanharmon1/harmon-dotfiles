# Brewfile for Harmon Dotfiles
# Install with: task install  (brew bundle --file=Brewfile)
#
# This is the REPO's own toolchain — the tools the Taskfile, lefthook hooks, and
# scripts/ invoke to lint/verify this repo. It is deliberately separate from
# `private_Brewfile`, which chezmoi deploys to ~/Brewfile (your full dev-machine
# package set). `.chezmoiignore` excludes this file so chezmoi never deploys it.

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

# Skills sync (scripts/sync-skills.sh reads .skills-sync.yaml)
brew "yq"

# Utilities
brew "direnv"
brew "jq"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "bat"
brew "tokei"
brew "gum"          # status dashboard rendering (scripts/status.sh)
brew "television"   # interactive task menu (`task` / task menu-tv → tv)
