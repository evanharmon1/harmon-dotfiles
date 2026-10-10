#!/usr/bin/env bash
# render-templates.sh — fail on any chezmoi template error, before `chezmoi
# apply` finds it on a host (issue #49). Run via `task validate`.
#
# Usage: render-templates.sh [SOURCE_DIR]   (default: the repo root)
#
# What it checks, read-only and without touching the real $HOME:
#   1. Every `*.tmpl` file (tracked, or untracked-but-not-ignored) renders on
#      its own. This names the exact file and variant that broke.
#   2. `.chezmoiignore` (itself a template) exists and renders, via
#      `chezmoi ignored`. Its absence is a failure: it is what keeps repo
#      tooling (README, Taskfile, scripts/**) out of $HOME.
#   3. The WHOLE source state computes: `chezmoi apply --dry-run
#      --exclude=scripts` against the empty throwaway destination. The
#      invariant is "chezmoi can compute the complete target state from this
#      source", so every template type chezmoi knows is evaluated without this
#      script listing file types: `.tmpl` files, `modify_` templates (fed their
#      current contents, empty here, the real first-apply case),
#      `.chezmoitemplates/` partials (via the includes that use them) and
#      `.chezmoiignore`. A dry run writes nothing and runs no scripts.
#   4. Every file in `.chezmoiscripts/` is a `run_` script that chezmoi picks
#      up (`chezmoi managed --include=scripts`). Naming is otherwise only
#      validated at apply time. The executable bit is deliberately not
#      checked: chezmoi runs scripts from a temporary copy, so it does not
#      need one in the source tree.
# All of the above run once per variant (below); every failure is collected
# and reported with the file name, then the script exits non-zero.
#
# Hermeticity: chezmoi runs under `env -i` with a throwaway HOME, config,
# cache and persistent state in one mktemp dir (removed on exit), so the
# developer's real chezmoi config/state and environment never influence the
# result. PATH holds only a symlink to `sh`, a stub `op` (so
# `onepasswordRead` never reaches the real 1Password) and, in the "gh"
# variants, a stub `gh` — see below.
#
# Variants. Templates branch on things that differ between machines; each is
# pinned so the check gives the same answer everywhere, and both sides of each
# branch are rendered:
#   - OS: `--override-data '{"chezmoi":{"os":...}}'` replaces `.chezmoi.os`
#     with darwin, then linux. Only template data is overridden: `stat` and
#     `lookPath` still answer for the runner (e.g. the linuxbrew `stat` branch
#     in the shell rc files renders whichever way the runner's filesystem
#     says; `.chezmoi.arch` and `.chezmoi.hostname` are not varied).
#   - gh: dot_config/private_git/config.tmpl calls `lookPath "gh"` and runs
#     `gh auth status` at render time. The "gh" variants put a stub `gh` that
#     reports success on PATH; the others have no `gh` at all. Real `gh` and
#     real credentials (GH_TOKEN, ~/.config/gh) are never consulted, so the
#     authenticated and unauthenticated branches both render in CI.
#   - container: `.chezmoiignore` skips a git config path when
#     REMOTE_CONTAINERS/CODESPACES is set or /.dockerenv exists; one variant
#     sets REMOTE_CONTAINERS=1 to render that branch. (/.dockerenv itself is
#     the runner's, so the unset variants render whichever way it says.)
# Not covered: Windows (no template targets it), host-specific data from a
# user's own chezmoi.toml (none is referenced by this source), and the
# *effects* of the rendered files — this proves they render, not that they
# are correct.
#
# modify_ templates read `.chezmoi.stdin`; step 3 runs them on empty stdin
# (a first apply) to prove they compute. Their behaviour on real existing
# files is tested in scripts/test-ai-config.sh.
#
# Without chezmoi: skipped with a message locally, a failure when CI=true
# (the pinned install lives in .github/actions/setup, #133).
set -euo pipefail

src="${1:-$(git rev-parse --show-toplevel)}"
src="$(cd "$src" && pwd -P)"

if ! command -v chezmoi >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
        echo "FAIL: chezmoi is not installed in CI, so templates cannot be rendered" >&2
        exit 1
    fi
    echo "SKIP: chezmoi is not installed; cannot render templates (CI installs a pinned chezmoi)"
    exit 0
fi
chezmoi_bin="$(command -v chezmoi)"
sh_bin="$(command -v sh)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/cache" "$work/bin-none" "$work/bin-gh"
# Stub `op` (1Password CLI): templates call onepasswordRead, and a render must
# never reach the real vault. chezmoi probes `op --version` to pick the CLI
# generation, then runs `op read`; both get canned answers.
cat >"$work/bin-none/op" <<'STUB'
#!/bin/sh
case "$*" in
    *--version*) echo 2.30.0 ;;
    *) echo stub ;;
esac
STUB
chmod +x "$work/bin-none/op"
cp "$work/bin-none/op" "$work/bin-gh/op"
ln -s "$sh_bin" "$work/bin-none/sh"
ln -s "$sh_bin" "$work/bin-gh/sh"
printf '#!/bin/sh\nexit 0\n' >"$work/bin-gh/gh"
chmod +x "$work/bin-gh/gh"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# chezmoi_run <os> <gh|nogh> <container|nocontainer> <chezmoi args...>
chezmoi_run() {
    local os="$1" gh="$2" container="$3"
    shift 3
    local path_dir="$work/bin-none"
    [ "$gh" = gh ] && path_dir="$work/bin-gh"
    local extra=()
    [ "$container" = container ] && extra=(REMOTE_CONTAINERS=1)
    env -i HOME="$work/home" PATH="$path_dir" "${extra[@]+"${extra[@]}"}" \
        "$chezmoi_bin" \
        --source "$src" \
        --config "$work/chezmoi.toml" \
        --destination "$work/home" \
        --cache "$work/cache" \
        --persistent-state "$work/state.boltdb" \
        --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" \
        --no-tty --no-pager \
        "$@"
}

templates=()
while IFS= read -r -d '' f; do
    [ -f "$src/$f" ] && templates+=("$f")
done < <(git -C "$src" ls-files -z --cached --others --exclude-standard -- '*.tmpl')
[ "${#templates[@]}" -gt 0 ] || fail "no *.tmpl files found under $src (is it a git work tree?)"

scripts=()
while IFS= read -r -d '' f; do
    [ -f "$src/$f" ] && scripts+=("$f")
done < <(git -C "$src" ls-files -z --cached --others --exclude-standard -- '.chezmoiscripts')

variants=(
    "darwin nogh nocontainer"
    "darwin gh nocontainer"
    "darwin nogh container"
    "linux nogh nocontainer"
    "linux gh nocontainer"
    "linux nogh container"
)

for variant in "${variants[@]}"; do
    # shellcheck disable=SC2086 # word-splitting the variant triple is the point
    set -- $variant
    os="$1" gh="$2" container="$3"
    label="os=$os $gh $container"

    for f in "${templates[@]}"; do
        if ! out="$(chezmoi_run "$os" "$gh" "$container" \
            execute-template --file --with-stdin "$src/$f" </dev/null 2>&1 >/dev/null)"; then
            fail "$f does not render ($label): $out"
        fi
    done

    if [ -f "$src/.chezmoiignore" ]; then
        if ! out="$(chezmoi_run "$os" "$gh" "$container" ignored 2>&1 >/dev/null)"; then
            fail ".chezmoiignore does not render, or the source state is invalid ($label): $out"
        fi
    else
        fail ".chezmoiignore is missing ($label): it keeps repo tooling out of \$HOME"
    fi

    # Whole source state: modify_ templates, .chezmoitemplates partials and
    # everything else chezmoi evaluates. Dry run: nothing is written or run.
    if ! out="$(chezmoi_run "$os" "$gh" "$container" \
        apply --dry-run --exclude=scripts 2>&1 >/dev/null </dev/null)"; then
        fail "chezmoi cannot compute the full target state ($label): $out"
    fi

    # Run scripts: once per OS is enough, they do not vary with gh/container.
    if [ "$gh" = nogh ] && [ "$container" = nocontainer ] && [ "${#scripts[@]}" -gt 0 ]; then
        if ! managed="$(chezmoi_run "$os" "$gh" "$container" managed --include=scripts 2>&1)"; then
            fail "chezmoi managed --include=scripts failed ($label): $managed"
        else
            for f in "${scripts[@]}"; do
                base="${f##*/}"
                dir="${f%/*}" # keeps any subdirectory under .chezmoiscripts/
                if [ "${base#run_}" = "$base" ]; then
                    fail "$f is not a run_ script, so chezmoi would deploy it as a file instead of running it"
                    continue
                fi
                name="${base#run_}"
                name="${name#once_}"
                name="${name#onchange_}"
                name="${name#before_}"
                name="${name#after_}"
                name="${name%.tmpl}"
                if ! printf '%s\n' "$managed" | grep -Fxq -- "$dir/$name"; then
                    fail "$f is not picked up as a run script ($label): expected $dir/$name in 'chezmoi managed --include=scripts'"
                fi
            done
        fi
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "render-templates: $failures failure(s)" >&2
    exit 1
fi
echo "render-templates: ${#templates[@]} template(s), .chezmoiignore and the full source state rendered, ${#scripts[@]} run script(s) checked, ${#variants[@]} variants"
