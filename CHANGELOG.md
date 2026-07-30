# Changelog

All notable changes to Harmon Dotfiles are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are cut manually with `task release:patch|minor|major` (never
automatically on merge).

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
