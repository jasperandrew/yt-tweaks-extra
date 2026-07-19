#!/usr/bin/env bash
# Bring everything up to date after upstream's main has moved, or after a
# fix/* branch changes: rebase fix branches onto upstream/main, rebuild
# `fixes`, rebase every feature/tooling/readme branch onto the new `fixes`,
# then rebuild `extra`.
#
# Safe to re-run: fast-forwarding main and rebasing an already current branch
# are both no-ops.
#
# If a rebase hits a conflict, this stops right there (set -e) so you can
# resolve it: fix the files, `git add`, `git rebase --continue`, then just
# re-run this script - branches already brought up to date are skipped over
# for free.
#
# Doesn't push anything. Once you're happy with the result:
#   git push --force-with-lease myfork main fixes <branch...> extra
set -euo pipefail
cd "$(dirname "$0")"

start_ref=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree/index isn't clean. Commit, stash, or discard first." >&2
    exit 1
fi

FIX_BRANCHES=(
    fix/options-page-live-refresh
    fix/left-sidebar-explore-more-selector
)

# Everything else `extra` is built from - rebased onto `fixes` so they build
# on top of already-fixed behavior. `tooling` and `readme` aren't features,
# but they rebase onto `fixes` the same way, so they live in this list too.
ONTO_FIXES=(
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

git fetch upstream

git checkout main
git merge --ff-only upstream/main

for b in "${FIX_BRANCHES[@]}"; do
    echo "--- rebasing $b onto upstream/main ---"
    git checkout "$b"
    git rebase upstream/main
done

./build-fixes.sh

for b in "${ONTO_FIXES[@]}"; do
    echo "--- rebasing $b onto fixes ---"
    git checkout "$b"
    git rebase fixes
done

# readme has no reason to keep every historical wording tweak as its own
# commit (unlike the feature/fix branches, it's not headed for an upstream
# PR), so squash it down to a single commit each time.
git checkout readme
if [ "$(git rev-list --count fixes..readme)" -gt 1 ]; then
    git reset --soft fixes
    git commit -m "Update readme"
fi

./build-extra.sh

git checkout "$start_ref"
