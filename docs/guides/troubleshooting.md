# Troubleshooting

Common issues in Harmon Dotfiles and how to fix them.

## Git hooks

- **"lefthook is not installed" on commit** — run `task install:hooks` (or `task install`).
- **Hook failures** — never bypass with `--no-verify`; run `task fix` and re-stage.

## Devcontainer

- **Stale tools after a Dockerfile change** — rebuild the container; prebuilt images come from GHCR (see `.github/workflows/devcontainer-build.yml`).
- **`/opt/homebrew/bin/gh: not found` on every git remote op** — the container is carrying a stale copy of the host's `~/.gitconfig` from before [issue #42](https://github.com/evanharmon1/harmon-dotfiles/issues/42). VS Code copies that file in on startup (`dev.containers.copyGitConfig`), and it used to contain the host's macOS `gh` path. Fixed at the source (the policy now lives in `~/.config/git/config`, which is never copied), but existing containers keep the old copy until they are replaced. Fix it one of two ways — **not** by deleting the file wholesale, which would also throw away the personal keys it is now the only source of (`core.excludesfile`, `core.editor`, the merge/diff tool prefs, both `includeIf` work-tree overrides, `commit.template`, and `user.name`/`user.email` on any container where post-create had no `$DEVCONTAINER_GIT_EMAIL` to write them from):
  - **Recreate the container** (preferred) — it picks up a fresh copy of the host's now-personal-only `~/.gitconfig`. Requires the host to have run `chezmoi apply` first.
  - **Edit the file in place** — delete just the `[credential "https://github.com"]`, `[credential "https://gist.github.com"]`, and both `[url "https://…"]` sections from the in-container `~/.gitconfig`. That is the whole fix; removing the reset lets the image's `~/.config/git/config` supply the helper again.
- **Missing secrets in the container** — locally, the env-file is provided by a **1Password environment** mounted at `.devcontainer/devcontainer.env` (see [devcontainers.md](devcontainers.md)); on Coder/Codespaces it's seeded from host/workspace env by `.devcontainer/scripts/init-env.sh`. Note `init-env.sh` does **not** call `op` — if values are missing locally, check the 1Password environment is authorized and mounted at the right path.

## CI

- **Required check missing on a PR** — ensure Build & Validate ran;
  required checks are `verify`, `security`.

TODO: add project-specific issues as they come up.
