# Onboarding

Getting productive in Harmon Dotfiles.

## Setup

1. Clone the repo: `git clone https://github.com/evanharmon1/harmon-dotfiles.git`
2. One-time machine setup (Homebrew): `task bootstrap`
3. Install dependencies and git hooks: `task install`
4. Authenticate the GitHub CLI: `gh auth login` — git pushes to GitHub
   authenticate through gh's token (ADR 0002), so this is what turns on
   HTTPS-with-gh git operations; until it runs, the gitconfig block is
   skipped and pushes behave as they did before.
5. Apply the dotfiles and verify everything works: `chezmoi apply`, then
   `task verify`

## Daily workflow

- Work on feature branches; direct commits to `main` are blocked.
- Conventional commit messages are enforced (`feat:`, `fix:`, `docs:`, ...).
- `task verify` before pushing; CI runs the same checks.
- Releases are intentional via release-please: merge the rolling release PR to
  publish (`task release:*` stays as a manual override).

## Where things are

See [the docs map](../README.md) for all documentation and the
[root README](../../README.md) for the project structure.

TODO: add project-specific context a new contributor needs.
