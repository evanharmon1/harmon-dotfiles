# Post-Generation Checklist — Harmon Dotfiles

<!--
AI AGENTS: This checklist is a human-maintained record for humans to check off.
Do not check, uncheck, rewrite, remove, reorder, normalize, reconcile, or
otherwise update its items based on repository state. Do not try to keep it
consistent with code, configuration, tags, releases, or external services.
Read-only inspection and reporting are allowed when requested, but never mutate
checklist state based on the findings. Only edit a checklist item when the human
user clearly and explicitly asks for that specific checklist update.
-->

Work through this after generating the repo from harmon-init. Delete items
that don't apply, then keep this file as a record of what was configured.

Run **`task status:setup`** at any point to audit setup completeness — local
credentials (gh, Codex), GitHub config, toolchain, devcontainer, and dev
environment — against the items below
(✓ done · ✗ missing · ? unknown · – n/a).

## 1. Local setup

- [ ] `task install` — Brewfile deps, and lefthook git hooks
- [ ] `task verify` passes locally
- [ ] **Vendor shared agent skills**: `.skills-sync.yaml` pins which harmon-devkit
      skill categories this repo gets (from your `skill_categories` answer). Set
      `ref` to the latest
      [harmon-devkit release](https://github.com/evanharmon1/harmon-devkit/releases)
      that ships the skill category layout, run `task sync:skills`, and commit
      `.agents/skills/` (also exposed to Claude at `.claude/skills/`) **and
      `.claude/agents/`** (the manifest's `agents:` block vendors shared
      subagents there at the same pinned ref). Until then the `verify:skills*` drift checks skip
      cleanly (CI + pre-push). **Pin bumps are a two-step:** edit `ref` in
      `.skills-sync.yaml`, then run `task skills:status` to see the current
      vendoring state without changing anything (add `-- --offline` for an
      offline snapshot). Then run `task sync:skills` and commit the refreshed
      `.claude/skills/` and `.claude/agents/` in the same PR. Renovate surfaces a new release in the
      Dependency Dashboard; approve it there to open the pin PR, then run the
      sync and push its output as a separate commit (do not amend Renovate's
      commit). Renovate cannot do the re-sync, so a ref-only commit fails the
      drift check.
- [ ] Verify `harmon-dotfiles.code-workspace` opens the repo's folder in VS Code and has a unique VS Code Workspace color. Then add any other related repos (e.g. other org repos) to the `folders` list in the workspace file so you have quick access to those repos
- [ ] Extend `.gitignore` for your stack — the template ships a base; add stack-specific entries via [gitignore.io](https://www.toptal.com/developers/gitignore)
- [ ] macOS: add a Raycast quicklink/alias that opens the `harmon-dotfiles.code-workspace`
- [ ] macOS (Bunch): scaffold the launcher with `task util:bunch-add` (if not generated at copier time), then `task util:bunch-install` to move it to iCloud and leave a `.meta/*.bunch` symlink (re-run install if missing)

## 2. GitHub repo settings

- [ ] **Confirm draft pull requests are available on this repo** — every agent
      PR opens as a draft and is promoted only by the readiness gate (AGENTS.md,
      "Dev Loop"). GitHub restricts draft PRs on **private** repositories to its
      paid plans, so on a private free-plan repo `gh pr create --draft` fails
      outright and the whole lifecycle stops at its first step. Check the current
      plan matrix in [GitHub's draft-PR
      docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request);
      if drafts are unavailable, make the repo public, upgrade the plan, or
      decide deliberately not to run agent workflows here — do not "fix" it by
      dropping `--draft`, which would make an open PR mean nothing again.
- [ ] **Automated settings** — run `task setup:github` (idempotent, safe to
      re-run): enables **Dependabot alerts** and **private vulnerability
      reporting** when public, and reconciles the repository's `CI_RUNS_ON`
      variable from the selected runner settings (the repository value
      intentionally takes precedence over an organization fallback). Every existing value is preserved on non-public
      repositories, and public repositories are standardized to
      `"ubuntu-latest"` even when the Copier answers or an existing variable
      select different routing. Re-run this task
      after changing Copier runner answers; an existing non-public value
      remains authoritative and must be changed intentionally by running
      `scripts/setup-github.sh` with `--replace-ci-runs-on`. Do not add
      `dependabot.yml`: Renovate owns routine
      and vulnerability-remediation PRs; Dependabot owns advisory alerts.
- [ ] Import the branch ruleset (see [architecture/branch-protection.md](architecture/branch-protection.md)) — do this once `build.yml` are on `main` so the required `verify`/`security` checks resolve. **Use the UI import:** Settings → Rules → Rulesets → **New ruleset ▸ Import a ruleset** → select `.github/Branch Protection Ruleset - Protect Main.json`. (Prefer the UI over `gh api … rulesets`: the API `POST` is not idempotent — re-running creates a duplicate ruleset — and currently rejects the `merge_queue` rule. To later change the ruleset, edit the existing one in the UI rather than re-importing.)
- [ ] **[human-only] Add `closing-keywords` to the live branch ruleset** — after
      the `closing-keywords` build job has reported once, edit the existing
      main-branch ruleset in Settings → Rules → Rulesets and add that exact
      required status check. Do not re-import the JSON solely for this change:
      GitHub creates a duplicate ruleset rather than updating the live one.
- [ ] **[human-only] Enable unattributed-changes approval in the live branch
      ruleset** — after a `copier update` adds this parameter, edit the existing
      main-branch ruleset in Settings → Rules → Rulesets and enable the matching
      additional-approval setting. Do not re-import the JSON: GitHub creates a
      duplicate ruleset rather than updating the live one.

- [ ] **Install and activate Renovate** — install the
      [Renovate app](https://github.com/apps/renovate) for **Only select
      repositories** and select this repo. In the Mend Developer Portal choose
      the **Renovate** product and **Scan and Alert** mode. Do not choose **Scan
      Only**: it puts Renovate in silent mode, which scans without creating
      checks, issues (including the Dependency Dashboard), or update/remediation
      PRs. This repo already has `renovate.json`; keep that configuration rather
      than replacing it with a generic onboarding config.
- [ ] **[human-only] Confirm CodeRabbit has no access** — for a repository that
      previously used it, remove this repo from the CodeRabbit GitHub App
      installation. Deleting `.coderabbit.yaml` and bot trust does not revoke
      existing App access.
- [ ] **[human-only] Connect Codex cloud review** — connect this repository in
      ChatGPT Codex settings, grant private-repository access if applicable,
      and confirm review activity is authored by GitHub actor ID `199175422`
      (`chatgpt-codex-connector[bot]`, type `Bot`).
- [ ] **[human-only] Disable Codex Automatic reviews** — turn **personal Auto
      review** off and set this repository's **Auto code review** preference to
      **Follow personal** — and its review **Trigger** to Follow personal too,
      since an "On every push" trigger sits dormant while Auto review is off
      and arms across every Follow-personal repo at once the moment the
      personal toggle changes. The draft-workbench lifecycle drives Codex with
      explicit `@codex review` requests while the PR is draft; left on,
      `gh pr ready` starts a *new* asynchronous review after the readiness gate,
      and non-draft stops truthfully meaning "ready for a human". Ticking this
      item records that all three knobs are set; once recorded it is settled
      configuration — nothing in the lifecycle gates on it — and the one thing
      worth reporting later is an unsolicited Codex review, the signature of
      the knobs drifting back on.
- [ ] **[human-only] Any other automatic reviewer must review drafts** — if you
      enable one (GitHub Copilot code review, for example), turn on its draft-review option.
      A reviewer that skips drafts first reports *after* promotion, so the
      readiness gate would hand a human a PR it had not actually reviewed.
      Leave it off rather than run it blind to the workbench.
- [ ] Actions secret: `CLAUDE_CODE_OAUTH_TOKEN` (claude-* workflows) — generate
      with `claude setup-token`; the value must start **`sk-ant-oat01-`** (an OAuth
      token, billed to your Claude subscription), **not** `sk-ant-api03-` (a raw API
      key, billed at pay-as-you-go API rates). Then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`
- [ ] **SAST coverage** — this profile has no CodeQL workflow, so Semgrep CE runs
      in `build.yml` for public and private repositories. Add CodeQL later if the
      repo gains supported first-party source: set `use_codeql=true`, select its
      `codeql_languages`, and ensure it is public (free) or has paid GitHub Code
      Security (private/internal).
- [ ] **Choose the Snyk posture** — the default is manual/local only via
      `task security:sast:snyk` and `task security:sca:snyk`; it is not part of
      `task security` or required PR CI. Free private-repository tests share the
      Snyk Organization's monthly quota, including local CLI tests. Leave the
      Snyk GitHub App off unless deliberately adopting its PR integration; its
      checks are not required by the default branch ruleset.
- [ ] **Optional scheduled Snyk** — leave this off for ordinary and free private
      repos. For a selected important public repo, re-render with
      `snyk_scan_schedule=weekly` (conservative) or `daily` (public or accepted
      unlimited OSS), set the generated workflow's `SNYK_TOKEN` Actions secret,
      and verify one manual run. Confirm Snyk classifies the public Git remote
      correctly. The workflow is advisory and never a required PR check.
- [ ] **Create** the CI GitHub App `evanharmon1-ci` by hand (one App per org;
      **Settings → Developer settings → GitHub Apps**), or reuse the org's existing one.
- [ ] **Install** the App on this repo — **Install App → Only select repositories**
      (the harmon-init repos that run release-please / claude-* / project-automation),
      **not "All"**. **Creating the App is not enough:** an App whose credentials are
      set but which is *not installed* on the repo makes
      `actions/create-github-app-token` fail at runtime with a **404**
      (`Not Found` — "not installed on this repository"). This is the single
      easiest step to miss.
- [ ] Set `CI_APP_CLIENT_ID` (Actions **variable**) + `CI_APP_PRIVATE_KEY` (Actions
      **secret**) — **pipe the `.pem` in** (never paste it; flattened newlines break
      the key), and **scope both to those same repos** (least privilege — the key can
      act as the App: commits, PRs, releases, workflow edits):

      ```bash
      gh secret set CI_APP_PRIVATE_KEY --org evanharmon1 \
        --visibility selected --repos <repo-a>,<repo-b> < evanharmon1-ci.private-key.pem
      gh variable set CI_APP_CLIENT_ID --org evanharmon1 \
        --visibility selected --repos <repo-a>,<repo-b> --body "<client-id>"  # Iv…-style, not the numeric App ID
      ```

      Personal account: use `--repo evanharmon1/harmon-dotfiles` instead of
      `--org`/`--visibility`/`--repos`. Re-running `--repos` **replaces** the list —
      re-run with the full list to add a repo. Drives release-please, the claude-*
      workflows, and project-automation; blast-radius + rotation in
      docs/architecture/security.md.
- [ ] GitHub Project: run `task setup:github-project` (needs
      `gh auth refresh -s project`) to create the owner's default project (titled
      `evanharmon1 Project`) and idempotently sync its `Status` pipeline and
      `Size` number field — see
      [project-management.md](project-management.md).
      On a personal account it also creates Priority/Product/Size as project
      fields (issue fields are org-only; there is deliberately no Domain or
      Layer field — see [project-management.md](project-management.md), "Label
      or field?"); status automation is a separate follow-up — the board is set
      up, but issue/PR status isn't auto-synced yet. Re-runs **append** any
      starter option a single-select field is missing (so a value added by a
      later harmon-init release lands on the next run) and never touch,
      reorder, or delete the options you added.
- [ ] **Upgrading from a release before harmon-init#875?**
      If this repo's board still carries `Domain`/`Layer` fields from an
      earlier release, they are not deleted automatically.
      Retiring them is a deliberate, irreversible operator step — see
      [project-management.md](project-management.md), "Migrating a board that
      still has one."
- [ ] **Upgrading from a release before harmon-init#1047
      (`method:*` → `strategy:*`)?** Run `task setup:github-labels` first so
      the `strategy:*` destinations exist, then use the read-only report and
      guarded maintenance flow below. For each live value among `oneshot`,
      `plan`, `plan-approved`, `orchestrate`, `council`, and `human-led`, pass
      one `--migrate method:<v>=strategy:<v>`; the guarded flow attempts to move
      associations for matching issues, PRs, and discussions found in its paginated snapshots,
      re-reads them, and only then allows `--prune` to remove zero-association
      retired labels.
- [ ] Labels: run `task setup:github-labels` to seed this repo's starter label
      families from `label-registry.json`      (see the generated taxonomy table in
      [project-management.md](project-management.md)) — grow `domain:` values
      there as the product's own problem-space vocabulary and `area:` values as
      its solution-space subsystems; both starter lists are a floor. `layer:`
      is product-independent and normally needs no edits. Labels are per-repo,
      so run it in each repo; org default labels (org Settings → Repository,
      UI-only) only seed new repos.
- [ ] **After a `copier update` that adds label families** (e.g. `tier:*` — a
      pure addition), re-run `task setup:github-labels` to provision the new
      labels here — it is additive and never deletes, so existing labels and
      the issues they sit on are untouched — then classify open issues with the
      added families. A RENAMED family (like `method:*` → `strategy:*` above)
      is not a pure addition — provision the new destinations first, then
      migrate the old associations before retiring their labels.
- [ ] **[human-only] Inspect live label drift before retiring anything** — keep
      the default setup path additive, then run
      `./scripts/setup-github-labels.sh --repo <owner/repo> --report-unregistered`
      with the same `--foreman` / `--release-please` profile flags used for
      setup when you want to mirror provisioning. Maintenance protection still
      includes every non-retired registered family, including gated tool labels,
      when those flags are omitted. This is read-only: it pages through the
      live labels, all-state issues and pull requests, and repository
      discussions, and reports separate association counts. An indeterminate read is a stop, not
      permission to clean up.
- [ ] **[human-only] Retire any legacy `agent:*` claim labels or pre-2026
      `codex`/`copilot` labels** — use the guarded maintenance flow, never a
      direct `gh label delete` or a hand-written association list. Perform its
      write path in a quiescent maintenance window: pause claim/release,
      Foreman, release-please, and other human/API label writers for the whole
      run. `--report-unregistered` is read-only, but its counts are a snapshot;
      run it again immediately before `--prune`.

      For fixed-family sources, these mappings are authoritative:
      `agent:claude-code` → `claim:claude`, `agent:codex` → `claim:gpt`,
      `agent:gemini-cli` → `claim:gemini`, `agent:kimi-k2` → `claim:kimi`, `agent:qwen-code` →
      `claim:qwen`, `suggest:codex` → `suggest:gpt`, and `claim:codex` →
      `claim:gpt`. Pass one repeatable `--migrate OLD=NEW` per exact live
      source, together with `--prune`; for example,
      `./scripts/setup-github-labels.sh --repo <owner/repo> --prune
      --migrate agent:gemini-cli=claim:gemini`. `--migrate` does not match a
      prefix, so each live model-level source needs its own mapping. The
      `OLD=NEW` form contains exactly one `=`; a label name containing `=` must
      be relabeled per record instead of passed to bulk migration. Move only
      the family segment for fixed mappings and preserve the recorded model
      suffix, e.g. `suggest:codex:sol` → `suggest:gpt:sol` and
      `claim:codex:sol` → `claim:gpt:sol`; model-level labels refine rather
      than replace their family-level label, and the command retains or adds
      both associations. If a recognized model-level
      destination is absent, the command creates it after confirmation by
      copying metadata from the live family label; missing family labels stop
      maintenance and require setup first.

      Use this association-migration path, not `gh label edit` or a hand-written
      create-then-delete sequence: the command validates a live registry
      destination or creates a recognized on-demand model destination as
      described above, attempts the association move for each matching issue,
      PR, and discussion found in its paginated snapshots, then permits
      `--prune` only when a fresh snapshot
      shows the source has zero associations. Enumerate
      model-level names explicitly with `gh label list --repo <owner/repo>
      --limit 1000 --json name --jq '.[].name' | grep -E
      '^(suggest|claim):(codex|copilot):'`; for each source, inspect all-state
      `gh issue list --label <old> --state all --limit 1000` **and**
      `gh pr list --label <old> --state all --limit 1000`. An exactly-full
      manual result is capped; increase the limit and rerun before writes. The
      maintenance path itself uses `gh api --paginate` and refuses an
      indeterminate read.

      Copilot is a broker, not a fixed family: `mai` is only the picker default
      and is never a guessed destination. Do **not** pass
      `agent:github-copilot*`, `suggest:copilot*`, or `claim:copilot*` to bulk
      `--migrate` — the command rejects broker-derived sources because one
      destination cannot represent mixed runtime records. For
      `suggest:copilot`, there is no claim/session record: re-express each
      issue/PR's planning intent as `suggest:<actual-family>` or drop the old
      association; do not rename it to `suggest:mai`. For `claim:copilot`,
      inspect each issue/PR's claim/session record and relabel that record to
      `claim:<actual-family>`; use `claim:mai` only when the record confirms
      MAI. Apply the same per-record distinction to
      `suggest:copilot:<model>`/`claim:copilot:<model>` and preserve a model
      suffix only after the actual family is known. Include Discussions in that
      per-record inventory: the read-only report gives their association count,
      and the Discussions UI or GraphQL API identifies the records to relabel.
      If a live claim's record is
      missing, settle it with its owner or leave the label untouched rather
      than guess. Add and verify the per-record destination before removing the
      old association; after every record is handled, a fresh zero-association
      snapshot may permit guarded `--prune` to attempt retiring the source.

      Before moving any in-flight `claim:*`/legacy `agent:*` marker, settle the
      claim or amend its durable record in the same sitting: its release path
      names the exact label it will remove, and moving only the issue/PR
      association strands the replacement marker. Interactive runs confirm on
      the TTY; automation must state destructive intent again with separate
      `--yes` (piped stdin is refused).

      The command verifies each migration around source removal, then takes one
      complete, bounded post-migration association snapshot before the deletion
      batch and fails closed on read/verification errors, but GitHub has no transaction or
      compare-and-swap that binds the final read to the following edit/DELETE.
      A concurrent writer can still change labels after that read and before
      the request, and the command cannot undo a successful concurrent
      mutation. If writers were not paused or any verification drifts, treat
      the operation as incomplete, reconcile live associations, and rerun in a
      new quiet window; do not infer association preservation from a successful
      exit alone; this is a guarded best-effort operation at that API boundary.
- [ ] Project views: create the starter views (Board / Triage / Agent queue /
      Planning / Mine) in the Project UI — Projects V2 has no view API,
      so this is a one-time manual step. Filters/layouts are in
      [project-management.md](project-management.md).
- [ ] GitHub Project auto-add (**adds every issue to the board**): in the
      Project's **Settings → Workflows**, turn on **"Auto-add to project"** and
      point it at this repo (filter `is:issue`, `is:pr`) so *every* new issue and
      PR lands on the board automatically, however it's created. GitHub's native
      built-in — no Actions or tokens, and it's the reliable way to guarantee
      coverage (the issue-form `projects:` key only covers form-created issues and
      needs a static project number). See
      [project-management.md](project-management.md).

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
