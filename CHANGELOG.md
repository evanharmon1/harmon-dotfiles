# Changelog

All notable changes to Harmon Dotfiles are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are cut manually with `task release:patch|minor|major` (never
automatically on merge).

## [0.9.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.8.1...v0.9.0) (2026-08-08)


### Features

* add additional repos to agy trustedWorkspaces ([5e83aff](https://github.com/evanharmon1/harmon-dotfiles/commit/5e83aff3ad0bd5fdcb4328e11a79b331a3772e31))
* add comprehensive list of safe read-only commands to agy allowlist ([103b228](https://github.com/evanharmon1/harmon-dotfiles/commit/103b228958d4a4148ac76cdf8edb13fdda92dfdc))
* add ls and git status to allowed commands in agy ([5ec2de0](https://github.com/evanharmon1/harmon-dotfiles/commit/5ec2de03041890a70a81e59b1a23a45142e93f3d))
* add platform repos to agy trustedWorkspaces ([1c5604c](https://github.com/evanharmon1/harmon-dotfiles/commit/1c5604c9aa6dbec5cffad894ba6400a726faa8a4))
* **agents:** add wildcards to safe command allowlist for agy ([f5e0811](https://github.com/evanharmon1/harmon-dotfiles/commit/f5e08119fd1c1324d61ca13a9df25632ea1bf3c8))
* **claude:** default to opus-4-8, add Herdr session hook, lower effort to medium ([612a6d8](https://github.com/evanharmon1/harmon-dotfiles/commit/612a6d8e591eca26665f9365f4e31c84349571c7))
* port agy hooks and setup adapter ([9d9c73c](https://github.com/evanharmon1/harmon-dotfiles/commit/9d9c73c740d3d19e65e722d0826a23b394d67586))
* port agy hooks and setup adapter ([a603d1c](https://github.com/evanharmon1/harmon-dotfiles/commit/a603d1c30764b9bb02d2d7fc2f9611e43dc3d5b1))


### Bug Fixes

* address codex P2s for hook resilience ([6c4f794](https://github.com/evanharmon1/harmon-dotfiles/commit/6c4f794c9cfde7c6dbbe1cbe858ba25d0bf52389))
* address codex P2s in session-start-context ([4ee0922](https://github.com/evanharmon1/harmon-dotfiles/commit/4ee09224b06b6c42dec6540314cdb3be85f37da1))
* **hooks:** address codex review findings on arg parsing ([538b9ed](https://github.com/evanharmon1/harmon-dotfiles/commit/538b9ed8663ee3d656e8d6111a1fd8f06ce0a2c1))
* **hooks:** address edge cases around remote owners and pathspecs ([f44ed07](https://github.com/evanharmon1/harmon-dotfiles/commit/f44ed07375e958921edc77f174d2728d83f21888))
* **hooks:** address edge cases around short option parsing and templating ([2f598fd](https://github.com/evanharmon1/harmon-dotfiles/commit/2f598fdbfaf69ae76fd5ec6a60521394da3b06a4))
* **hooks:** address further codex review findings on hook robustness ([133628f](https://github.com/evanharmon1/harmon-dotfiles/commit/133628f6b91a74f9184a1545195960a54642e0f4))
* **hooks:** address further codex review findings on isolated stderr and .git matching ([1afef7c](https://github.com/evanharmon1/harmon-dotfiles/commit/1afef7cb74fbd1e57e60d7ad0eec4164472a95fa))
* **hooks:** address further edge cases from codex review ([e24aaaa](https://github.com/evanharmon1/harmon-dotfiles/commit/e24aaaa7974c7c8bcfb44cc927998d9a9eb715ca))
* **hooks:** address further edge cases from codex review ([db4be8d](https://github.com/evanharmon1/harmon-dotfiles/commit/db4be8d83cfba837a4d4e7d94f3ff40b3a7c6586))
* **hooks:** escape jinja delimiters in bash sed command ([8651c45](https://github.com/evanharmon1/harmon-dotfiles/commit/8651c45f825b49efd8d93241a4063c10e5be0978))
* **hooks:** fail open on missing commit-msg task and increase timeout ([f3a294f](https://github.com/evanharmon1/harmon-dotfiles/commit/f3a294f985b2415e4c711e46ecefe26d152dce56))
* **hooks:** join repeated message arguments with actual newlines ([9dc66d9](https://github.com/evanharmon1/harmon-dotfiles/commit/9dc66d9ad2fa52430a300607cccd33a25ff77ac0))
* **hooks:** match parsed remote owner exactly ([598d31c](https://github.com/evanharmon1/harmon-dotfiles/commit/598d31cf0c9904fadea3239146de0630e23502e4))
* **hooks:** support gtimeout and improve block-no-verify parsing ([8e8b27d](https://github.com/evanharmon1/harmon-dotfiles/commit/8e8b27d883867918acb1bf02b0f84dd33d58afcd))
* map file_path for adapter hooks ([0a6af9d](https://github.com/evanharmon1/harmon-dotfiles/commit/0a6af9d29ed0b7ac5bb14f3b1d331a1988d9c3c7))
* resolve lint errors in hooks ([8e143ec](https://github.com/evanharmon1/harmon-dotfiles/commit/8e143ecf0f22cb6234b7ac0a33688c22b087eccf))

## [0.8.1](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.8.0...v0.8.1) (2026-08-03)


### Bug Fixes

* move ADR 0002 git transport config to the host XDG layer ([fefaefe](https://github.com/evanharmon1/harmon-dotfiles/commit/fefaefe8957d9bdae4a0064f24b12d44643ba90f))
* move ADR 0002 git transport config to the host XDG layer ([d182816](https://github.com/evanharmon1/harmon-dotfiles/commit/d182816413790f000999ce6631a7d2c8aa3b4777)), closes [#42](https://github.com/evanharmon1/harmon-dotfiles/issues/42)

## [0.8.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.7.0...v0.8.0) (2026-08-01)


### Features

* authenticate GitHub git operations via gh credential helper ([9b354fd](https://github.com/evanharmon1/harmon-dotfiles/commit/9b354fd80cb9b9a4c112241bed13fa153025d57f))
* authenticate GitHub git operations via gh credential helper ([625d67d](https://github.com/evanharmon1/harmon-dotfiles/commit/625d67db5096262b872032bb25693cc04e1e9d5d))


### Bug Fixes

* place github.com credential block before includeIf sections ([d2b5c13](https://github.com/evanharmon1/harmon-dotfiles/commit/d2b5c13647fb2cd4c66c2060f3726663279b40dc))
* render the github.com block only when gh is authenticated ([999b27f](https://github.com/evanharmon1/harmon-dotfiles/commit/999b27f30dcad27e74ad636a44d15e8579775d4e))
* rewrite gist and port-443 SSH endpoints to HTTPS too ([bfde849](https://github.com/evanharmon1/harmon-dotfiles/commit/bfde84988f677e49d835451078e66a569b0a74ba))
* scope the apply-time auth check to github.com ([8a1ab4c](https://github.com/evanharmon1/harmon-dotfiles/commit/8a1ab4c251a5b5eba9a22813488ee58dbf30e3c6))
* update constitution rule 1 stop condition to require shepherding ([6f6972d](https://github.com/evanharmon1/harmon-dotfiles/commit/6f6972d762422fcbeef1c9bcdd4a46f7e0a9a0ee))
* update constitution rule 1 stop condition to require shepherding ([310a32d](https://github.com/evanharmon1/harmon-dotfiles/commit/310a32dbe691bfe2040e0b1208ff129e0443b6ba)), closes [#26](https://github.com/evanharmon1/harmon-dotfiles/issues/26)

## [0.7.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.6.0...v0.7.0) (2026-07-30)


### Features

* add Claude GLM launcher ([244f75b](https://github.com/evanharmon1/harmon-dotfiles/commit/244f75b3997139643ab896ccc88e2c40223345a2))
* add Claude GLM launcher ([cc954eb](https://github.com/evanharmon1/harmon-dotfiles/commit/cc954eba8f4c4cc2fc4f66b97540b42450b07f46))

## [0.6.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.5.0...v0.6.0) (2026-07-30)


### Features

* **shell:** add Claude provider wrappers ([5235e12](https://github.com/evanharmon1/harmon-dotfiles/commit/5235e12685d0d5d730c2756780931d57a8e1c86c))
* **shell:** add Claude provider wrappers ([079f195](https://github.com/evanharmon1/harmon-dotfiles/commit/079f1951210afe9ca0c6330260debcb583113c66))
* **shell:** load Claude keys with 1Password ([503c66f](https://github.com/evanharmon1/harmon-dotfiles/commit/503c66f8782870bdc0deb7b385ab52a1caf39164))


### Bug Fixes

* **shell:** preserve TTY for Claude wrappers ([dcfda80](https://github.com/evanharmon1/harmon-dotfiles/commit/dcfda80c29dfe5015b0fda0881fe08c940f95eac))
* **shell:** preserve TTY for Claude wrappers ([51e6af0](https://github.com/evanharmon1/harmon-dotfiles/commit/51e6af051606bb4de18f2ccf8cc8e0443416f996))
* **shell:** silence unavailable connector warning ([e1de5cf](https://github.com/evanharmon1/harmon-dotfiles/commit/e1de5cf68766976e91ec52007eb28fd50d948643))
* **shell:** silence unavailable connector warning ([4fdfa20](https://github.com/evanharmon1/harmon-dotfiles/commit/4fdfa200bd53e41ed5219bf19d26f56318d444d1))

## [0.5.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.4.0...v0.5.0) (2026-07-29)


### Features

* **agent-deck:** manage config with chezmoi ([d5d4f9e](https://github.com/evanharmon1/harmon-dotfiles/commit/d5d4f9ebc1476aaa8b51e05fb2971f8bf3f020da))
* **agent-deck:** manage config with chezmoi ([94ef7a4](https://github.com/evanharmon1/harmon-dotfiles/commit/94ef7a44ed17e25e0d0d323c434cc12ca9021cb2))

## [0.4.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.3.0...v0.4.0) (2026-07-05)


### Features

* **claude:** constitution rule 7 — password managers are read-only ([cda6648](https://github.com/evanharmon1/harmon-dotfiles/commit/cda664894e1c79ba30f8a878abf7ff31a411adf7))
* **claude:** constitution rule 7 — password managers are read-only ([0352d6b](https://github.com/evanharmon1/harmon-dotfiles/commit/0352d6bfa0141296f879f0bc9c36b82b38ffc6d5))

## [0.3.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.2.0...v0.3.0) (2026-07-04)


### Features

* declare chezmoi management with a header in every managed file ([880143b](https://github.com/evanharmon1/harmon-dotfiles/commit/880143bc6ff1c2a62e489ff637e052c31e07ad09))
* declare chezmoi management with a header in every managed file ([a5fcf10](https://github.com/evanharmon1/harmon-dotfiles/commit/a5fcf105f3ca4e8dca119248b8e3a59da4aec513))


### Bug Fixes

* header the Linux-variant ghostty/aichat sources too (deploy on non-macOS) ([d005559](https://github.com/evanharmon1/harmon-dotfiles/commit/d0055592ab9e0c8bc8adce55925fbf13164fa86a))

## [0.2.0](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.1.1...v0.2.0) (2026-07-04)


### Features

* **claude:** add global constitution (~/.claude/CLAUDE.md) + merge-guard ask rules ([85117ee](https://github.com/evanharmon1/harmon-dotfiles/commit/85117ee59097e36867bcba6a9614ddc2c7e40ebb))
* **claude:** global constitution file + merge-guard ask rules ([30e4f5f](https://github.com/evanharmon1/harmon-dotfiles/commit/30e4f5f92fe476014371eca2dbc8decbaefc3baa))


### Bug Fixes

* stop globally ignoring *.zip ([2a38a61](https://github.com/evanharmon1/harmon-dotfiles/commit/2a38a61ee72b2cfd917333ca65168fe363d4981a))
* stop globally ignoring *.zip ([8ee3bdf](https://github.com/evanharmon1/harmon-dotfiles/commit/8ee3bdfb09f3cecca5fcfa740336a3a4ec7d2004))

## [0.1.1](https://github.com/evanharmon1/harmon-dotfiles/compare/v0.1.0...v0.1.1) (2026-07-03)


### Bug Fixes

* add root Brewfile for repo tooling; stop chezmoi deploying repo files ([fa83407](https://github.com/evanharmon1/harmon-dotfiles/commit/fa83407d4e44fde7497d0fdb162b10c16f6bd484))

## [Unreleased]

### Added

- Initial repository scaffolding generated from [harmon-init](https://github.com/evanharmon1/harmon-init) on 2026-06-27.
