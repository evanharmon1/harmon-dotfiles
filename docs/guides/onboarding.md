# Onboarding

Getting productive in Harmon Dotfiles.

## Setup

1. Clone the repo: `git clone https://github.com/evanharmon1/harmon-dotfiles.git`
2. One-time machine setup (Homebrew): `task bootstrap`
3. Install dependencies and git hooks: `task install`
4. Verify everything works: `task verify`

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
