# 2. Git operations over HTTPS via the gh credential helper

Date: 2026-07-31 (revised 2026-08-03 — see [Revisions](#revisions))

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

- `~/.config/git/config` (chezmoi-managed, `dot_config/private_git/config.tmpl`)
  configures host-scoped credential helpers for `https://github.com` and
  `https://gist.github.com`: an empty `helper =` reset (so gh, not an
  inherited osxkeychain entry, is authoritative) followed by
  `helper = !<gh-path> auth git-credential`, with the absolute gh path
  resolved via chezmoi's `lookPath` so GUI clients with a sparse PATH
  (VS Code, Sourcetree) can invoke it. The whole block renders only when gh
  is installed **and authenticated for github.com** (`gh auth status
  --hostname github.com` at apply time — a bare `gh auth status` is
  host-agnostic and would also pass on a GHES-only machine): before
  `gh auth login` — or if auth is later lost — the block is omitted so the
  machine keeps whatever push behavior it already had, and the policy
  (re)activates on the next apply once gh authenticates.
- `[url "https://github.com/"] insteadOf` rewrites every GitHub SSH URL form
  for fetch and push — the scp form (`git@github.com:`), both `ssh://` forms,
  and the port-443 endpoint (`ssh://git@ssh.github.com[:443]/`) — and
  `[url "https://gist.github.com/"] insteadOf` does the same for gist SSH
  remotes, so legacy SSH remotes, submodules, and SSH-form clone URLs
  transparently use HTTPS without per-repo surgery.
- **This policy is the host's, and lives in the host's config only.** Git
  config splits by concern: *environment* config (credential-helper strategy,
  transport rewrites) belongs to whatever owns the machine, while `~/.gitconfig`
  carries *personal* config (identity, aliases, diff/merge tool prefs) and
  nothing else. That split is what keeps the policy out of containers — VS Code
  Dev Containers copies only `~/.gitconfig` from the host on startup
  (`dev.containers.copyGitConfig`), never `~/.config/git/config`, so a Linux
  container inherits identity without inheriting a macOS `gh` path. In a
  devcontainer the equivalent environment layer is the harmon-init image's own
  `~/.config/git/config`.
- Do **not** run `gh auth setup-git` on dotfiles-managed machines, and avoid
  `git config --global` for these keys — both write `~/.gitconfig`, which git
  reads *after* `~/.config/git/config` and which would therefore shadow this
  policy rather than reinforce it. The template already encodes what setup-git
  writes.
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
  machine that pushes — the Brewfile covers installation and the onboarding
  guide covers `gh auth login`; the apply-time guard means a machine missing
  either simply keeps its previous behavior instead of breaking. The
  OAuth token's blast radius is broader than a git-only SSH key, but it
  already exists on the machine, is centrally revocable, and using it for git
  retires a second long-lived credential rather than adding exposure.
- The rewrite is machine-wide, affecting human git use too; workflows that
  genuinely require SSH transport to github.com (none are known today) would
  need an explicit `git -c` override.
- Multiple GitHub accounts on one host share the active `gh` account's token;
  a path-scoped `includeIf` gitconfig can override the helper per directory
  tree if that ever becomes necessary — `~/.config/git/config` is read before
  `~/.gitconfig`, so the `includeIf` sections there still expand after the
  reset and have the last word (the include must supply its own empty
  `helper =` reset plus its helper to win).
- Git only reads `~/.config/git/config` while `XDG_CONFIG_HOME` is unset or
  empty. Nothing in these dotfiles sets it; if that changes, this file moves
  with it or the policy silently stops applying.
- The devcontainer fleet runs the same policy in-container, but owns its own
  copy in the image's `~/.config/git/config` (harmon-init) rather than
  inheriting the host's — so each layer's `gh` path is correct for its own
  filesystem and neither can clobber the other. Behavior stays uniform across
  host, bot containers, and VS Code dev containers.

## Revisions

**2026-08-03 — moved the policy from `~/.gitconfig` to `~/.config/git/config`**
([issue #42](https://github.com/evanharmon1/harmon-dotfiles/issues/42),
companion [harmon-init#542](https://github.com/evanharmon1/harmon-init/issues/542)).
Amended in place rather than superseded by a new ADR: the decision — HTTPS to
GitHub, authenticated by `gh` — is unchanged. Only the file the policy is
written to changed, and leaving the original text in place would have described
a configuration that no longer exists.

As originally written, the policy rendered into `~/.gitconfig`. VS Code Dev
Containers copies that file — and only that file — from the host into every
container it starts, so Linux containers inherited a macOS `gh` path and printed
`/opt/homebrew/bin/gh: not found` on every remote operation, while the block's
empty `helper =` reset discarded the working helper the container had installed
for itself.

The file was reaching containers by **copy, not by in-container render**: the
in-container file contained `/opt/homebrew/bin/gh`, and chezmoi's `lookPath`
resolves on the machine performing the apply, so a macOS path can only have come
from a macOS render. Confirmed against a running devcontainer, which has no
chezmoi installed and no `~/.gitconfig` of its own. This rules out the obvious
alternative fix — a container guard inside the template — as a no-op: the
template renders on the host, where any container check is false, and the result
is copied in regardless. Splitting personal config from environment config, and
keeping the environment half in the file nothing copies, is what actually holds.
