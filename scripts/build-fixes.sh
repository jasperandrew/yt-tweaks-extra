#!/usr/bin/env bash
# Rebuild `fixes` from scratch: upstream/main + every fix/* branch,
# cherry-picked in order. This is the base feature branches rebase onto, so
# they can be developed against already-fixed behavior instead of upstream's.
#
# Re-run whenever a fix branch changes, then rebase feature branches onto the
# new `fixes` tip (sync.sh does this end to end), and force-push:
#   git push --force-with-lease myfork fixes
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
git checkout fixes 1>/dev/null
git reset --hard upstream/main

echo

# Resolved to explicit commit SHAs (not left as ranges) so a single
# cherry-pick call preserves branch order - see build-extra.sh for why.
BRANCHES=(
    fix/options-page-live-refresh
    fix/left-sidebar-explore-more-selector
)

commits=()
for b in "${BRANCHES[@]}"; do
    while IFS= read -r sha; do
        commits+=("$sha")
    done < <(git rev-list --reverse "upstream/main..$b")
done

if [ "${#commits[@]}" -gt 0 ]; then
    git cherry-pick "${commits[@]}"
else
    echo Nothing to do, exiting...
    exit 0
fi

echo
git log --oneline upstream/main..fixes

echo
git checkout "$start_ref" 1>/dev/null
echo
echo "Branch 'fixes' build complete. Push with: git push --force-with-lease myfork fixes"
