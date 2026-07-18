#!/bin/bash
#
# helios-mirror.sh — mirror the working repo to the iCloud redundancy copy.
#
# WHY: the repo lives at ~/Developer/HeliosConsole and pushes to GitHub. That
# is two copies, but they can fail together — a bad force-push, a deleted
# branch, or an account problem takes out the remote while a dead Mac takes
# out the local. This adds a third, independent copy in iCloud.
#
# It also protects the files git CANNOT: .gitignore'd machine-local config
# (Deployment/build-pkg.local.sh — signing identity + mirror path, present on
# this Mac and nowhere else) would otherwise be unrecoverable.
#
# WHAT IT COPIES
#   - the full working tree, INCLUDING .git (history, branches, tags, stash)
#   - gitignored machine-local files (build-pkg.local.sh)
#   - a `git bundle` snapshot (see BUNDLE below)
#
# WHAT IT SKIPS
#   - build/      2+ GB of regenerable Xcode output
#   - dist/       .pkg archive; build-pkg.sh already mirrors each new pkg there
#                 via MIRROR_DIST, so this script leaves it alone entirely
#   - .DS_Store   Finder noise
#
# BUNDLE: iCloud syncs file-by-file and can evict or partially sync a directory
# of thousands of tiny loose git objects, which is exactly how a .git directory
# is shaped. So alongside the tree we write a single-file `git bundle` — one
# atomic artifact carrying complete history that either syncs or doesn't. If
# the mirrored .git is ever suspect, clone from the bundle instead:
#
#     git clone HeliosConsole.bundle HeliosConsole
#
# SAFETY: this is a ONE-WAY push, repo -> iCloud, with --delete. Never edit the
# iCloud copy: your changes there are not in git and the next run erases them.
#
# Usage:  ./scripts/helios-mirror.sh          # sync
#         ./scripts/helios-mirror.sh --check  # report drift, change nothing
#
set -euo pipefail

REPO="${HELIOS_REPO:-$HOME/Developer/HeliosConsole}"
MIRROR="${HELIOS_MIRROR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/_APPS_IM_BUILDING/Vibe/HELIOS/HeliosConsole}"
BUNDLE_NAME="HeliosConsole.bundle"

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

info() { printf '==> %s\n' "$1"; }
fail() { printf '❌ %s\n' "$1" >&2; exit 1; }

[[ -d "$REPO/.git" ]] || fail "Not a git repo: $REPO"
mkdir -p "$MIRROR"

# Excludes. dist/ is deliberately absent from --delete's reach: it is excluded,
# and rsync does not delete excluded paths on the destination, so the pkg
# archive build-pkg.sh maintains there survives untouched.
EXCLUDES=(
    --exclude='build/'
    --exclude='dist/'
    --exclude='DerivedData/'
    --exclude='.DS_Store'
    --exclude='*.xcuserstate'
)

if [[ $CHECK_ONLY -eq 1 ]]; then
    info "Dry run — reporting drift only, nothing will be written"
    rsync -an --delete --itemize-changes "${EXCLUDES[@]}" "$REPO/" "$MIRROR/" \
        | grep -v '^\.d\.\.t' || true
    echo
    info "Nothing above = mirror is current."
    exit 0
fi

# Warn on uncommitted work: the mirror will faithfully copy it, but it is not
# on GitHub, so it exists in exactly two places until committed and pushed.
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
    printf '⚠️  Working tree has uncommitted changes — mirroring them as-is.\n'
    printf '    They are NOT on GitHub; commit and push for the third copy.\n'
fi

# Purge Finder droppings from the MIRROR before syncing. They are excluded
# from transfer, and rsync will not delete a directory that still has an
# excluded file in it — so a folder removed from the repo would linger in the
# mirror forever, kept alive by a stray .DS_Store, and fail the drift check.
# (--delete-excluded would fix that too, but it would also wipe dist/, which
# is excluded precisely so build-pkg.sh's pkg archive survives.)
find "$MIRROR" -name '.DS_Store' -type f -delete 2>/dev/null || true

info "Mirroring $REPO"
info "       -> $MIRROR"
# With the droppings gone, a directory the repo no longer has is genuinely
# empty, so --delete removes it on its own. Do NOT add a blanket empty-dir
# purge here: the repo legitimately contains empty directories (e.g.
# .xcworkspace/xcshareddata/swiftpm/configuration) and deleting those just
# makes the next sync recreate them — permanent phantom drift.
rsync -a --delete "${EXCLUDES[@]}" "$REPO/" "$MIRROR/"

# Single-file complete-history snapshot (see BUNDLE note above).
info "Writing git bundle (all refs)…"
git -C "$REPO" bundle create "$MIRROR/$BUNDLE_NAME" --all --quiet
git -C "$REPO" bundle verify "$MIRROR/$BUNDLE_NAME" >/dev/null 2>&1 \
    || fail "Bundle failed verification — mirror tree is synced, but the bundle is bad."

# Record what this snapshot represents, so a future you can tell at a glance
# how current the copy is without diffing it.
{
    printf 'Helios repo mirror — written by scripts/helios-mirror.sh\n'
    printf 'Synced:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Branch:  %s\n' "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    printf 'Commit:  %s\n' "$(git -C "$REPO" log -1 --pretty='%H  %s')"
    printf 'Dirty:   %s\n' "$([[ -n "$(git -C "$REPO" status --porcelain)" ]] && echo 'YES — uncommitted changes included' || echo 'no')"
    printf '\nThis is a ONE-WAY copy. Do not edit it; the next sync overwrites.\n'
    printf 'Restore:  git clone %s HeliosConsole\n' "$BUNDLE_NAME"
    printf 'Excluded: build/ DerivedData/ (regenerable); dist/ is maintained\n'
    printf '          separately by build-pkg.sh MIRROR_DIST.\n'
} > "$MIRROR/MIRROR_INFO.txt"

info "Verifying…"
# NOTE the `|| true`: grep exits 1 when it filters out every line, which here
# is the SUCCESS case (no drift). Under `set -o pipefail` that would abort the
# script just as it was about to report success.
DRIFT=$({ rsync -an --delete --itemize-changes "${EXCLUDES[@]}" "$REPO/" "$MIRROR/" \
        | grep -vE '^\.d\.\.t|MIRROR_INFO|\.bundle' || true; } | wc -l | tr -d ' ')
[[ "$DRIFT" == "0" ]] || fail "Post-sync drift detected ($DRIFT path(s)) — mirror may be incomplete."

printf '\n✅ Mirror current — %s\n' "$(du -sh "$MIRROR" | cut -f1)"
printf '   bundle: %s (%s)\n' "$BUNDLE_NAME" "$(du -h "$MIRROR/$BUNDLE_NAME" | cut -f1)"
