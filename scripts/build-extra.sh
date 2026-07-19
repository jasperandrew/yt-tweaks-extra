#!/usr/bin/env bash
# Rebuild `extra` from scratch: reset to `fixes` (upstream/main + every fix
# branch - see build-fixes.sh), then cherry-pick each feature branch's commit
# plus extra's own tooling commits, in a fixed order. Produces a fully linear
# history (no merge commits) every time.
#
# Assumes feature branches are already rebased onto `fixes` (sync.sh does
# this end to end). Re-run whenever a feature branch or `fixes` changes, then
# review and force-push:
#   git push --force-with-lease myfork extra
set -euo pipefail
cd "$(dirname "$0")"

start_ref=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)

# A conflict from a previous run left a cherry-pick in progress: resuming it
# (once you've resolved and `git add`ed the conflict) continues through
# everything still left below, rather than starting the whole rebuild over
# and hitting the same conflict again.
if git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "A cherry-pick is in progress with unresolved conflicts. Resolve them, 'git add' the result, then re-run this script." >&2
        exit 1
    fi
    git cherry-pick --continue
    report_done
    exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree/index isn't clean. Commit, stash, or discard first." >&2
    exit 1
fi

git fetch upstream
git checkout extra 1>/dev/null
git reset --hard fixes

echo

# Order matters: tooling and readme land last of all. `git cherry-pick` with
# several ranges in one call doesn't preserve the order they're given in (it
# re-sorts the combined commits), so each range is resolved to its own
# explicit, ordered commit list first, and those are concatenated in the
# order below. Passed to a single cherry-pick (not one call per branch) so a
# conflict partway through can be resumed with `git cherry-pick --continue`
# instead of restarting the whole sequence.
BRANCHES=(
    feature/convert-shorts
    feature/speed-control
    feature/header-hide-buttons
    feature/comments-toggle
    feature/auto-like
    feature/hide-related-sidebar
    feature/hide-ask-button
    feature/redirect-homepage
    tooling
    readme
)

commits=()
for b in "${BRANCHES[@]}"; do
    while IFS= read -r sha; do
        commits+=("$sha")
    done < <(git rev-list --reverse "fixes..$b")
done

if [ "${#commits[@]}" -gt 0 ]; then
    git cherry-pick "${commits[@]}"
else
    echo Nothing to do, exiting...
    exit 0
fi

echo
git log --oneline fixes..extra

echo
git checkout "$start_ref" 1>/dev/null
echo
echo "Branch 'extra' build complete. Push with: git push --force-with-lease myfork extra"
