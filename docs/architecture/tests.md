# Tests

How testing works in Harmon Dotfiles.

## Layers

| Layer | Tool | Command |
|---|---|---|
| Lint / static analysis | shellcheck, yamllint, markdownlint, actionlint | `task check` |
| Source render | chezmoi isolated dry run | `task test:chezmoi` |
| Task/hook guards | shell assertions | `task test:tasks` |
| Application security | Semgrep CE locally | `task security:sast` |
| Optional second opinion | Snyk Code + Open Source, manual | `task security:sast:snyk` / `task security:sca:snyk` |
| Secrets | gitleaks | `task security:secrets` |
| Dependencies | package-manager audit | `task security:audit` |

## Conventions

- The chezmoi test renders into a temporary destination with external refreshes
  disabled; it never applies changes to the real home directory.
- `task verify` is the local merge gate; CI runs the same task targets.
