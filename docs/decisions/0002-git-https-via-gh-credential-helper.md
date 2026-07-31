# 2. Git operations over HTTPS via the gh credential helper

Date: 2026-07-31

## Status

Accepted

## Context

Git pushes to GitHub intermittently failed when the 1Password SSH agent was
locked (`sign_and_send_pubkey: ... communication with agent failed`), blocking
work until a manual per-command HTTPS workaround was run
([issue #37](https://github.com/evanharmon1/harmon-dotfiles/issues/37)). The
workaround pushed to a raw URL rather than the named remote, which left the
local remote-tracking ref stale and made `git status` report a misleading
"ahead 1" after a *successful* push.

Meanwhile HTTPS pushes already "worked" on the primary Mac only by accident:
Homebrew's `/opt/homebrew/etc/gitconfig` sets `credential.helper=osxkeychain`
and a `github.com` entry of unknown provenance, scope, and freshness happened
to exist in the login keychain. That state was unmanaged, undocumented,
macOS-only, and a second shadow credential alongside the `gh` token that
agents and humans already keep alive for every PR workflow.

## Decision

HTTPS is the default git transport for GitHub on dotfiles-managed machines,
authenticated by `gh`:

- `~/.gitconfig` (chezmoi-managed, `private_dot_gitconfig.tmpl`) configures
  host-scoped credential helpers for `https://github.com` and
  `https://gist.github.com`: an empty `helper =` reset (so gh, not an
  inherited osxkeychain entry, is authoritative) followed by
  `helper = !<gh-path> auth git-credential`, with the absolute gh path
  resolved via chezmoi's `lookPath` so GUI clients with a sparse PATH
  (VS Code, Sourcetree) can invoke it. The whole block is omitted on machines
  where gh is not installed.
- `[url "https://github.com/"] insteadOf` rewrites both SSH forms
  (`git@github.com:` and `ssh://git@github.com/`) for fetch and push, so
  legacy SSH remotes, submodules, and SSH-form clone URLs transparently use
  HTTPS without per-repo surgery.
- Do **not** run `gh auth setup-git` on dotfiles-managed machines — it edits
  `~/.gitconfig`, which chezmoi owns and will overwrite. The template already
  encodes what setup-git writes.
- SSH remains the transport for non-GitHub remotes (nothing else is
  rewritten), and per-command overrides (`git -c url...`) remain possible.

Rejected alternatives:

- **Keep the SSH agent unlocked** (shell-rc / launchd / 1Password integration):
  treats the symptom, adds a machine-level service to maintain, and agents
  require `gh` auth regardless — HTTPS removes a dependency instead of
  propping one up.
- **Rely on the osxkeychain status quo**: works today on one machine, but is
  implicit, unrotatable-by-convention, and absent on Linux.
- **Flip remotes per repo without `insteadOf`**: leaves any future or
  arbitrary SSH URL (fresh clones, submodules, `related-repos.txt` entries)
  exposed to the same lockout.

## Consequences

- One credential maintains git+API auth for GitHub (the `gh` token) instead
  of two (token + SSH key); the SSH agent is out of the push path, so the
  lockout failure class is gone for GitHub remotes.
- The stale "ahead 1" side effect disappears: pushes go through the named
  remote again, so tracking refs update normally.
- Push auth now depends on `gh` being installed and authenticated on every
  machine that pushes (already true via the Brewfile and onboarding). The
  OAuth token's blast radius is broader than a git-only SSH key, but it
  already exists on the machine, is centrally revocable, and using it for git
  retires a second long-lived credential rather than adding exposure.
- The rewrite is machine-wide, affecting human git use too; workflows that
  genuinely require SSH transport to github.com (none are known today) would
  need an explicit `git -c` override.
- Multiple GitHub accounts on one host share the active `gh` account's token;
  a path-scoped `includeIf` gitconfig can override the helper per directory
  tree if that ever becomes necessary.
- The devcontainer fleet applies the same policy in-container
  (`url.insteadOf` in `post-create-common.sh`), so behavior is uniform
  across host, bot containers, and VS Code dev containers.
