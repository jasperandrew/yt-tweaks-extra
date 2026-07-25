#!/usr/bin/env bash
# fixes - rebuild `fixes` from scratch: upstream/main + every fix/* branch,
#         cherry-picked in order. This is the base feature branches rebase
#         onto, so they can be developed against already-fixed behavior
#         instead of upstream's.
# extra - rebuild `extra` from scratch: reset to `fixes`, then cherry-pick
#         each feature branch's commit plus extra's own tooling/readme
#         commits, in a fixed order. Produces a fully linear history (no
#         merge commits) every time. Assumes feature branches are already
#         rebased onto `fixes` (`sync` does this end to end).
# sync      - bring everything up to date after upstream's main has moved, or
#             after a fix/* branch changes, then rebuild fixes and extra. See
#             run_sync below for the full sequence.
# xpi - package `extra` into yt-tweaks.xpi, switching to it first and
#             back afterwards regardless of the branch this was invoked from.
#
# If a rebase or cherry-pick (any of the three) hits a conflict git rerere
# already has a recorded resolution for, it's resolved and staged
# automatically and the operation carries on. A genuinely new conflict still
# stops the script right there so you can resolve it: fix the files,
# `git add`, then `git rebase --continue` or `git cherry-pick --continue`
# (whichever the printed message names), then just re-run this same command -
# work already brought up to date is skipped over for free.
#
# Doesn't push anything - rebuilding always creates fresh commit objects, new
# SHAs, even where nothing meaningfully changed, so `sync` reports which
# branches actually differ from myfork (by tree, not SHA) and prints the exact
# push command for just those.
#
# Usage: build.sh fixes|extra|sync|xpi
set -euo pipefail
cd "$(dirname "$0")"

# Rebased onto upstream/main, feed into `fixes` (build_fixes).
FIX_BRANCHES=(
    fix/options-page-live-refresh
    fix/left-sidebar-explore-more-selector
)

# Everything else `extra` is built from - rebased onto `fixes` so they build on
# top of already-fixed behavior. `tooling` and `readme` aren't features, but
# they rebase onto `fixes` the same way, so they land in this list too. Order
# matters here: tooling and readme land last of all when cherry-picked into
# `extra` (build_extra) - see resolve_commits for why that's safe to rely on.
FEATURE_BRANCHES=(
    feature/convert-shorts
    feature/speed-control
    feature/header-hide-buttons
    feature/comments-toggle
    feature/auto-like
    feature/hide-related-sidebar
    feature/hide-ask-button
    feature/redirect-homepage
    feature/hide-search-bar
    feature/compact-header-watch-only
    tooling
    readme
)

# Resolves a list of branches to a single, ordered list of explicit commit
# SHAs: each branch's own commits (base..branch), one branch after another in
# the order given. Needed because `git cherry-pick` with several ranges in one
# call doesn't preserve the order they're given in (it re-sorts the combined
# commits) - explicit SHAs, concatenated ourselves, do.
resolve_commits() {
    local base="$1"; shift
    for b in "$@"; do
        git rev-list --reverse "$base..$b"
    done
}

# Whether a git sequencer of the given kind ("cherry-pick" or "rebase") has a
# stopped, in-progress operation right now.
_sequencer_in_progress() {
    case "$1" in
        cherry-pick) git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null ;;
        # REBASE_HEAD, unlike CHERRY_PICK_HEAD, lingers like ORIG_HEAD even
        # after a rebase finishes cleanly - the rebase-merge/rebase-apply
        # state directory (removed on completion) is the reliable signal.
        rebase) test -d "$(git rev-parse --git-path rebase-merge)" || test -d "$(git rev-parse --git-path rebase-apply)" ;;
    esac
}

# Continues a stopped sequencer of the given kind without prompting for a
# commit message.
_sequencer_continue() {
    case "$1" in
        cherry-pick) git cherry-pick --continue --no-edit ;;
        # rebase --continue has no --no-edit of its own (confirmed: it's a
        # hard error) - GIT_EDITOR=true gets the same "keep it, don't prompt"
        # effect.
        rebase) GIT_EDITOR=true git rebase --continue ;;
    esac
}

# Drives a cherry-pick or rebase sequence to completion, whether starting
# fresh ($2.. is the command to run) or resuming one already in progress
# (called with just the kind). rerere.autoupdate may have already fully
# resolved and staged a given conflict by the time control comes back - when
# that's so, this continues on instead of stopping; it only stops and reports
# if a conflict is left with actual unresolved (<<<<<<<) hunks.
drive_sequencer() {
    local kind="$1"; shift
    local status=0
    if [ "$#" -gt 0 ]; then
        "$@" || status=$?
    fi

    while _sequencer_in_progress "$kind"; do
        if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
            echo "A $kind conflict needs manual resolution. Resolve it, 'git add' the result, then re-run this script." >&2
            exit 1
        fi
        status=0
        _sequencer_continue "$kind" || status=$?
    done

    if [ "$status" -ne 0 ]; then
        exit "$status"
    fi
}

# $1 is both the sequencer kind and the git subcommand name for cherry-pick
# and rebase alike, so one wrapper covers both: drive cherry-pick <shas...>,
# drive rebase <upstream>.
drive() {
    local kind="$1"; shift
    if [ "$#" -gt 0 ]; then
        drive_sequencer "$kind" git "$kind" "$@"
    else
        drive_sequencer "$kind"
    fi
}

# Fetches upstream and myfork at most once per process - run_sync calls
# build_fixes and build_extra directly, and all three would otherwise each
# fetch again for no reason (nothing changes on the remote between them in a
# single run). myfork is fetched too so differs_from_myfork below has
# up-to-date remote-tracking refs to compare against.
_fetched=""
ensure_fetched() {
    if [ -z "$_fetched" ]; then
        git fetch upstream
        git fetch myfork
        _fetched=1
    fi
}

# Whether $1's tree differs from myfork/$1 (or myfork doesn't have it yet).
# Rebuilding always creates fresh commit objects - new SHAs - even when
# nothing meaningfully changed (cherry-pick and rebase both do this), so this
# compares trees rather than SHAs to tell whether a push is actually needed.
differs_from_myfork() {
    if ! git rev-parse -q --verify "refs/remotes/myfork/$1" >/dev/null; then
        return 0
    fi
    ! git diff --quiet "myfork/$1" "$1" --
}

# $1's ahead/behind relationship to myfork/$1, in the same compact bracket
# notation `git status -sb`/`git branch -vv` use (e.g. "[ahead 2, behind 2]")
# rather than git's fully-spelled-out prose - this gets printed once per
# branch, and the prose form is unreadable at that density. Commit-count
# (SHA) based, not tree-based, so it can say "ahead N" even where the tree
# content is unchanged - rebuilding always creates fresh commits, so that's
# expected, not a contradiction. Exits 0 if $1 is out of date (should be
# pushed), 1 if it's already up to date, so callers can get both the printed
# status and the push decision from one call.
branch_status() {
    if ! git rev-parse -q --verify "refs/remotes/myfork/$1" >/dev/null; then
        echo "no myfork/$1"
        return 0
    fi

    local behind ahead
    read -r behind ahead < <(git rev-list --left-right --count "myfork/$1...$1")

    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        echo "up to date"
        return 1
    elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        echo "[ahead $ahead, behind $behind]"
    elif [ "$ahead" -gt 0 ]; then
        echo "[ahead $ahead]"
    else
        echo "[behind $behind]"
    fi
}

# Exits early with a clear message if the working tree/index isn't clean -
# every command here resets/rebases/cherry-picks and needs a clean start.
require_clean_worktree() {
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree/index isn't clean. Commit, stash, or discard first." >&2
        exit 1
    fi
}

# Checks out $1 (the branch this invocation started on, captured before it
# did anything else) and reports whether $2 actually needs pushing.
finish_build() {
    git checkout "$1" 1>/dev/null
    echo
    if differs_from_myfork "$2"; then
        echo "Branch '$2' build complete. Push with: git push --force-with-lease myfork $2"
    else
        echo "Branch '$2' build complete - matches myfork/$2 already, nothing to push."
    fi
}

# Rebuilds $1 from scratch: resets it to $2, then cherry-picks the branches
# named in $3 (an array name, e.g. FIX_BRANCHES) onto it, reporting an
# upstream/main..$1 log of what landed - build_extra's reset base is `fixes`,
# but its completion log intentionally reports the range since upstream/main,
# not just since `fixes`.
#
# Defined as its own function (not inlined per-target in the case dispatch at
# the bottom) so run_sync can call build_fixes/build_extra directly mid-run -
# by the time run_sync has rebased feature/fix branches, the working tree has
# been `git checkout`ed to branches that don't have a scripts/ directory at
# all, so re-invoking this file as a separate process would fail to find it
# on disk.
build_branch() {
    local target="$1" reset_base="$2" branches_name="$3"
    local -n branches="$branches_name"

    local start_ref
    start_ref=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)

    # A conflict from a previous run left a cherry-pick in progress: resuming
    # it continues through everything still left below, rather than starting
    # the whole rebuild over and hitting the same conflict again.
    if _sequencer_in_progress cherry-pick; then
        drive cherry-pick
        finish_build "$start_ref" "$target"
        return 0
    fi

    require_clean_worktree

    # Remembered so that below, if the rebuild turns out to be byte-identical
    # to what was already here, the branch can be put back exactly as it was
    # instead of keeping the fresh (but redundant) commits reset+cherry-pick
    # always creates - unset if $target doesn't exist yet (first ever build).
    local old_tip
    old_tip=$(git rev-parse -q --verify "$target" 2>/dev/null) || true

    ensure_fetched
    git checkout "$target" 1>/dev/null
    git reset --hard "$reset_base"

    echo

    local commits
    mapfile -t commits < <(resolve_commits "$reset_base" "${branches[@]}")

    if [ "${#commits[@]}" -gt 0 ]; then
        drive cherry-pick "${commits[@]}"
        echo
        git log --oneline "upstream/main..$target"
    else
        echo Nothing to do, exiting...
    fi

    # cherry-pick (and the reset above) always produces fresh commit objects,
    # even when nothing about the actual content changed. If that's all this
    # run did, put $target back exactly where it was - keeps its SHA (and
    # push status) stable, and lets rebases of branches built on top of it
    # (run_sync's rebase loops) recognize they're already up to date instead
    # of cascading a no-op content change into fresh commits of their own.
    if [ -n "$old_tip" ] && git diff --quiet "$old_tip" "$target" --; then
        git reset --hard "$old_tip"
        echo
        echo "No content changes - kept existing $target."
    fi

    echo
    finish_build "$start_ref" "$target"
}

# Rebuild `fixes` from scratch: upstream/main + every fix/* branch,
# cherry-picked in order. This is the base feature branches rebase onto, so
# they can be developed against already-fixed behavior instead of upstream's.
build_fixes() { build_branch fixes upstream/main FIX_BRANCHES; }

# Rebuild `extra` from scratch: reset to `fixes` (upstream/main + every fix
# branch - see build_fixes), then cherry-pick each feature branch's commit
# plus extra's own tooling commits, in a fixed order. Produces a fully linear
# history (no merge commits) every time.
build_extra() { build_branch extra fixes FEATURE_BRANCHES; }

# Packages src/ into an installable, unsigned .xpi (manifest.json at the
# archive root). Always builds from `extra` - that's the branch meant for
# distribution - regardless of which branch this was invoked from, then
# switches back. Requires Firefox's xpinstall.signatures.required = false to
# install.
build_xpi() {
    local start_ref
    start_ref=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)

    require_clean_worktree
    git checkout extra 1>/dev/null

    python3 - <<'PY'
import zipfile, os
src, out = '../src', '../yt-tweaks.xpi'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in files:
            if f.startswith('.'):
                continue
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
print('built', out)
PY

    git checkout "$start_ref" 1>/dev/null
}

# Bring everything up to date after upstream's main has moved, or after a
# fix/* branch changes: rebase fix branches onto upstream/main, rebuild
# `fixes`, rebase every feature/tooling/readme branch onto the new `fixes`,
# then rebuild `extra`. Safe to re-run: fast-forwarding main and rebasing an
# already current branch are both no-ops, and branches/builds already
# brought up to date are skipped over for free. Doesn't push anything.
run_sync() {
    local start_ref
    start_ref=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)

    require_clean_worktree

    ensure_fetched

    git checkout main
    git merge --ff-only upstream/main

    for b in "${FIX_BRANCHES[@]}"; do
        echo "--- rebasing $b onto upstream/main ---"
        git checkout "$b"
        drive rebase upstream/main
    done

    build_fixes

    for b in "${FEATURE_BRANCHES[@]}"; do
        echo "--- rebasing $b onto fixes ---"
        git checkout "$b"
        drive rebase fixes
    done

    # readme has no reason to keep every historical wording tweak as its own
    # commit (unlike the feature/fix branches, it's not headed for an
    # upstream PR), so squash it down to a single commit each time.
    git checkout readme
    if [ "$(git rev-list --count fixes..readme)" -gt 1 ]; then
        git reset --soft fixes
        git commit -m "Update readme"
    fi

    build_extra

    echo
    echo "--- push status ---"
    local all_branches=(main "${FIX_BRANCHES[@]}" fixes "${FEATURE_BRANCHES[@]}" extra)
    local width=0
    for b in "${all_branches[@]}"; do
        [ "${#b}" -gt "$width" ] && width="${#b}"
    done

    local changed=()
    for b in "${all_branches[@]}"; do
        local status
        if status=$(branch_status "$b"); then
            changed+=("$b")
        fi
        printf '  %-*s %s\n' "$width" "$b" "$status"
    done

    echo
    if [ "${#changed[@]}" -gt 0 ]; then
        echo "Push with: git push --force-with-lease myfork ${changed[*]}"
    else
        echo "Nothing to push - myfork is already up to date."
    fi

    git checkout "$start_ref"
}

case "${1:-}" in
    fixes) build_fixes ;;
    extra) build_extra ;;
    sync) run_sync ;;
    xpi) build_xpi ;;
    *)
        echo "Usage: $0 fixes|extra|sync|xpi" >&2
        exit 1
        ;;
esac
