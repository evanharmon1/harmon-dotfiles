# Tests

How testing works in Harmon Dotfiles.

## Layers

| Layer | Tool | Command |
|---|---|---|
| Lint / static analysis | shellcheck, yamllint, markdownlint, actionlint | `task check` |
| Template rendering | chezmoi (pinned; `.github/actions/setup`) | `task validate` |
| Behavioral tests | bash scripts in `scripts/test-*.sh` | `task test:<name>` (run by `task verify`) |
| Tests (aggregate) | TODO: `task test` is still a placeholder; `verify` runs each `test:*` target directly | `task test` |
| Application security | Semgrep CE locally | `task security:sast` |
| Optional second opinion | Snyk Code + Open Source, manual | `task security:sast:snyk` / `task security:sca:snyk` |
| Secrets | gitleaks | `task security:secrets` |
| Dependencies | package-manager audit | `task security:audit` |

## Conventions

- Test files live in `tests/` at the repo root (or co-located per framework convention).
- `task verify` is the local definition-of-done gate. CI runs the same task targets.
- Per-target behavioral tests live in `scripts/test-*.sh` and are wired to
  `task test:<name>` targets that `verify` runs — e.g. `task test:claude-config`
  exercises the `.chezmoiscripts/` run script that enables Claude Code Remote
  Control, against a throwaway `HOME` so the real `~/.claude.json` is untouched.
- `task validate` (`scripts/render-templates.sh`) renders every `*.tmpl` and
  `.chezmoiignore` with chezmoi, hermetically (throwaway HOME/config/state, stub
  `op` and `gh` on PATH), once per variant: `.chezmoi.os` forced to darwin and
  linux, `gh` present and absent, and a container environment. It also asserts
  every `.chezmoiscripts/` file is a `run_` script that
  `chezmoi managed --include=scripts` picks up. `task test:render-templates`
  proves broken templates, a broken `.chezmoiignore`, an untracked template, a
  misnamed run script and a break in each render-time branch all fail and are
  named. Without chezmoi it skips locally and fails when `CI=true`.
  Not covered: that rendered output is *correct* (only that it renders),
  `.chezmoi.arch`/hostname variants, and `stat`/`lookPath` answers other than
  `gh`, which come from the runner's filesystem (e.g. the linuxbrew branch).
- TODO: document coverage expectations and fixtures as the suite grows.
