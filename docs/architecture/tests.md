# Tests

How testing works in Harmon Dotfiles.

## Layers

| Layer | Tool | Command |
|---|---|---|
| Lint / static analysis | shellcheck, yamllint, markdownlint, actionlint | `task check` |
| Source render | chezmoi isolated dry run | `task test:chezmoi` |
| Task/hook guards | shell assertions | `task test:tasks` |
| Secrets | gitleaks | `task security:secrets` |

## Conventions

- The chezmoi test renders into a temporary destination with external refreshes
  disabled; it never applies changes to the real home directory.
- `task verify` is the local merge gate; CI runs the same task targets.
