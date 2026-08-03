# Troubleshooting

Common issues in Harmon Dotfiles and how to fix them.

## Git hooks

- **"lefthook is not installed" on commit** — run `task install:hooks` (or `task install`).
- **Hook failures** — never bypass with `--no-verify`; run `task fix` and re-stage.

## Devcontainer

- **Stale tools after a Dockerfile change** — rebuild the container; prebuilt images come from GHCR (see `.github/workflows/devcontainer-build.yml`).
- **`/opt/homebrew/bin/gh: not found` on every git remote op** — the container is carrying a stale copy of the host's `~/.gitconfig` from before [issue #42](https://github.com/evanharmon1/harmon-dotfiles/issues/42). VS Code copies that file in on startup (`dev.containers.copyGitConfig`), and it used to contain the host's macOS `gh` path. Fixed at the source (the policy now lives in `~/.config/git/config`, which is never copied), but existing containers keep the old copy: recreate the container, or delete the in-container `~/.gitconfig` and let the image's `~/.config/git/config` take over.
- **Missing secrets in the container** — locally, the env-file is provided by a **1Password environment** mounted at `.devcontainer/devcontainer.env` (see [devcontainers.md](devcontainers.md)); on Coder/Codespaces it's seeded from host/workspace env by `.devcontainer/scripts/init-env.sh`. Note `init-env.sh` does **not** call `op` — if values are missing locally, check the 1Password environment is authorized and mounted at the right path.

## CI

- **Required check missing on a PR** — ensure Build & Validate ran;
  required checks are `verify`, `security`.

TODO: add project-specific issues as they come up.
