# Post-Generation Checklist — Harmon Dotfiles

Work through this after generating the repo from harmon-init. Delete items
that don't apply, then keep this file as a record of what was configured.

Run **`task status:setup`** at any point to audit setup completeness — GitHub
config, toolchain, devcontainer, and dev environment — against the items below
(✓ done · ✗ missing · ? unknown · – n/a).

## 1. Local setup

- [ ] `task install` — Brewfile deps, and lefthook git hooks
- [ ] `task verify` passes locally
- [ ] Verify `harmon-dotfiles.code-workspace` opens the repo's folder in VS Code and has a unique VS Code Workspace color. Then add any other related repos (e.g. other org repos) to the `folders` list in the workspace file so you have quick access to those repos
- [ ] Extend `.gitignore` for your stack — the template ships a base; add stack-specific entries via [gitignore.io](https://www.toptal.com/developers/gitignore)
- [ ] macOS: add a Raycast quicklink/alias that opens the `harmon-dotfiles.code-workspace`
- [ ] macOS: confirm the project is in your Bunch — the `.meta/*.bunch` symlink (→ iCloud Bunches) is tracked; run `task util:bunch-add` to re-create it if missing

## 2. GitHub repo settings

- [ ] **Automated settings** — run `task setup:github` (idempotent, safe to
      re-run): enables **Dependabot alerts** and **private vulnerability
      reporting**, sets the `FULL_SECURITY_SCAN` variable (CodeQL). Do NOT add dependabot.yml — Renovate owns version updates.
- [ ] Import the branch ruleset (see [architecture/branch-protection.md](architecture/branch-protection.md)) — do this once `build.yml` is on `main` so the required `verify`/`security` checks resolve. **Use the UI import:** Settings → Rules → Rulesets → **New ruleset ▸ Import a ruleset** → select `.github/Branch Protection Ruleset - Protect Main.json`. (Prefer the UI over `gh api … rulesets`: the API `POST` is not idempotent — re-running creates a duplicate ruleset — and currently rejects the `merge_queue` rule. To later change the ruleset, edit the existing one in the UI rather than re-importing.)

- [ ] Install the [Renovate app](https://github.com/apps/renovate) on the repo
- [ ] Install the [CodeRabbit app](https://github.com/apps/coderabbitai) on the repo (`.coderabbit.yaml` is pre-configured)
- [ ] Actions secrets: `CLAUDE_CODE_OAUTH_TOKEN` (claude-* workflows),
      `SNYK_TOKEN` (snyk tasks)
- [ ] CI GitHub App `evanharmon1-ci`: create it by hand for this org (one App
      per org; **Settings → Developer settings → GitHub Apps**), or reuse the
      org's existing one;
      install it on this repo, then set `CI_APP_ID` (Actions
      **variable**) + `CI_APP_PRIVATE_KEY` (Actions **secret**) — org-level for
      an org, per-repo for a personal account. Drives release-please, the
      claude-* workflows, and project-automation. See docs/architecture/security.md.

## 3. Framework scaffolding (conventions-only template)

- [ ] Add the project's primary toolchain; extend Taskfile `build`/`test` accordingly

## 4. Secrets & environment

- [ ] For local `.env` needs, use **1Password Environments** (mounts a virtual
      `.env`; secrets never hit disk or git) or `op run`/`op inject`. Commit only
      `.env.example`-style files

## 5. Docs & meta

- [ ] Fill in the `TODO:` markers in README.md and docs/ (architecture diagram first)
- [ ] Confirm README badges render (Actions URLs are correct once CI runs)
- [ ] Initial release when ready: `task release:init` (v0.1.0) — releases stay manual
- [ ] Stay current with harmon-init: periodically run `copier update --trust` to pull
      template improvements (a three-way merge — your own edits are preserved). The
      standardize-repo skill (`update` mode) automates this and verifies the result.
