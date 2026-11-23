#!/usr/bin/env bash
# test/check-companion-freshness.sh — is the vendored offensive/companion/ subtree BEHIND htpx's latest release?
# ──────────────────────────────────────────────────────────────────────────────
# The vendored offensive/companion/ here is a git-subtree copy of dotgibson/htpx (the
# standalone red<->blue pentest companion; provenance in companion.lock). Nothing on
# THIS side tracked whether that copy had fallen behind upstream — so a fix landing in
# htpx could sit un-pulled here indefinitely. This is the consumer-side freshness
# watcher: it asks whether htpx has published a RELEASE this repo has not pulled. A
# behind result is the NUDGE to run scripts/sync-companion.sh, not a hard error in
# normal development — so it lives in a SCHEDULED workflow.
#
# RELEASES, NOT THE BRANCH TIP. The companion advances on htpx release tags (htpx's
# fan-out syncs this repo on each tag; #296/#297/#359 were all tag syncs), but this
# watcher used to compare companion_sha against htpx `main`. htpx's main takes CI-only
# bot commits between releases (Renovate action bumps, workflow rules) that never reach
# the corpus, so the scheduled run stayed red for eight weeks after v3.3.0 over two such
# commits (cleared by a sync to main in #375), and would go red again after every sync.
# Now "current" means the newest v* release commit is the vendored commit OR an ancestor
# of it: a lock synced past the release by hand (scripts/sync-companion.sh with no --ref
# pulls main) is current too. Ancestry needs history, so the check fetches htpx's
# commits only (--filter=tree:0, no trees or blobs) into a throwaway bare repo; equality
# alone, which is all test/check-core-freshness.sh needs for core's exact release pins,
# would call such a lock behind. With no release tags upstream it falls back to the
# branch tip, the old behaviour.
#
# This mirrors test/check-core-freshness.sh (the watcher for the vendored core/
# subtree) and its newest-v*-tag lookup, but differs in the lock file (companion.lock),
# its field names (companion_repo / companion_branch / companion_sha), the ancestry test
# above, and the remediation (scripts/sync-companion.sh --ref <tag>, not a raw
# `git subtree pull`).
#
# Exit codes (matching dotfiles-core's drift-check convention — see
# core/scripts/update-plugins.sh --check, and test/check-core-freshness.sh):
#   0  current, OR a graceful skip (no git, offline/restricted, not a subtree checkout)
#   2  vendored offensive/companion/ is BEHIND htpx's latest release (the nudge to sync)
#   1  a genuine hard failure (e.g. a malformed companion.lock)
# The workflow branches on these so a skip, a drift, and a real error each render the
# right step summary. Override the upstream/branch with COMPANION_UPSTREAM / COMPANION_BRANCH
# (the branch is what the ancestry fetch reads, and the comparison when no release exists).
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

# Palette + glyphs from the VENDORED shared bash UX lib (core/lib/ux.sh) — ONE colour/glyph
# rule instead of hand-rolled copies that drift. If core/ is incomplete the lib won't be
# readable, so fall back to no colour and ASCII glyphs rather than fail to source it; the
# explicit companion.lock presence check below is what actually decides "not a subtree checkout".
if [[ -r "$REPO/core/lib/ux.sh" ]]; then
  # shellcheck source=/dev/null
  source "$REPO/core/lib/ux.sh"
  c_g=$UX_GRN c_y=$UX_YEL c_r=$UX_RED c_0=$UX_RST
else
  c_g='' c_y='' c_r='' c_0=''
fi
# ASCII fallbacks when ux.sh is absent; when it's present these are already the
# locale-correct glyph (✓/⚠/… on UTF-8, ok/!/… otherwise), so := leaves them be.
: "${UX_OK:=ok}" "${UX_WARN:=!}" "${UX_ERR:=x}" "${UX_INFO:=-}"

skip() {
  printf '%s%s%s %s\n' "$c_y" "$UX_INFO" "$c_0" "$*"
  exit 0
}

# A non-subtree checkout has no vendored companion/ or companion.lock to compare — skip
# cleanly rather than report a misleading "behind".
[[ -d offensive/companion ]] || skip "check-companion-freshness: no vendored offensive/companion/ (not a subtree checkout?)"
command -v git >/dev/null 2>&1 || skip "check-companion-freshness: git unavailable"

# Read the recorded vendored commit from companion.lock (the O(1) offline provenance stamp
# written by scripts/sync-companion.sh). Same field idiom that sync-companion.sh uses.
# offensive/companion/ exists (asserted above), so this IS a subtree checkout — a
# missing/unreadable companion.lock is a broken repo state, not "not a subtree", and
# skipping it would silently disable the drift signal. Fail HARD (exit 1) instead.
if [[ ! -r companion.lock ]]; then
  printf '%s%s%s check-companion-freshness: offensive/companion/ present but companion.lock missing/unreadable — broken subtree state\n' \
    "$c_r" "$UX_ERR" "$c_0" >&2
  exit 1
fi
SPLIT="$(sed -n 's/^companion_sha=//p' companion.lock | head -n1)"
# A present-but-malformed lock would make the TIP-vs-SPLIT compare below report a false
# "behind". This is a real misconfiguration, not drift, so fail HARD (exit 1) with a
# clear message rather than emit a misleading verdict.
if [[ ! "$SPLIT" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s%s%s check-companion-freshness: companion.lock has an invalid companion_sha (%s) — expected a 40-char hex SHA\n' \
    "$c_r" "$UX_ERR" "$c_0" "${SPLIT:-empty}" >&2
  exit 1
fi

# Upstream repo/branch come from the lock too (override with COMPANION_UPSTREAM / COMPANION_BRANCH).
# companion_repo is recorded as an owner/name slug (dotgibson/htpx); derive the HTTPS URL the
# same way sync-companion.sh does when no override is given.
REPO_SLUG="$(sed -n 's/^companion_repo=//p' companion.lock | head -n1)"
LOCK_BRANCH="$(sed -n 's/^companion_branch=//p' companion.lock | head -n1)"
[[ -n "$REPO_SLUG" ]]   || { printf '%s%s%s check-companion-freshness: companion_repo missing from companion.lock\n' "$c_r" "$UX_ERR" "$c_0" >&2; exit 1; }
[[ -n "$LOCK_BRANCH" ]] || { printf '%s%s%s check-companion-freshness: companion_branch missing from companion.lock\n' "$c_r" "$UX_ERR" "$c_0" >&2; exit 1; }

UPSTREAM="${COMPANION_UPSTREAM:-https://github.com/$REPO_SLUG.git}"
BRANCH="${COMPANION_BRANCH:-$LOCK_BRANCH}"

# Resolve BRANCH to an explicit refs/heads/<branch> so ls-remote can't match a same-named
# tag (a bare name is a ref PATTERN). A caller may still pass a full refs/… via COMPANION_BRANCH.
case "$BRANCH" in
refs/*) ref="$BRANCH" ;;
*) ref="refs/heads/$BRANCH" ;;
esac
# GIT_TERMINAL_PROMPT=0 keeps every network call non-interactive (never block a scheduled
# run on a credential prompt). `--` forces end-of-options: UPSTREAM is overridable
# (COMPANION_UPSTREAM), and git would treat a leading-dash value as an option.
GLR() { GIT_TERMINAL_PROMPT=0 git ls-remote "$@" 2>/dev/null; }

# The branch tip doubles as the connectivity probe: empty means unreachable (or a branch
# that does not exist), which stays a graceful skip, as before.
TIP="$(GLR -- "$UPSTREAM" "$ref" | awk 'NR==1{print $1}')"
[[ -n "$TIP" ]] || skip "check-companion-freshness: cannot reach $UPSTREAM ($BRANCH) — offline/restricted?"

# Newest RELEASE: plain vX.Y.Z tags only. A pre-release (v3.4.0-rc1) is not a release, and
# `sort -V` would rank it above v3.4.0's final anyway. Peel an annotated tag to its commit
# (^{}); a lightweight tag has no peeled line, so fall back to the raw object.
REL_TAG="$(GLR --tags --refs -- "$UPSTREAM" 'v*' | sed -n 's#.*refs/tags/##p' |
  grep -E '^v[0-9]+(\.[0-9]+)*$' | sort -V | tail -n1)"

current() {
  printf '%s%s%s vendored offensive/companion/ is current %s (%s)\n' "$c_g" "$UX_OK" "$c_0" "$1" "${SPLIT:0:12}"
  exit 0
}

if [[ -z "$REL_TAG" ]]; then
  # No releases upstream: the branch tip is all there is to compare against.
  CMP_NAME="$BRANCH (no v* release tags found)"
  CMP_SHA="$TIP"
  [[ "$CMP_SHA" != "$SPLIT" ]] || current "with $UPSTREAM@$BRANCH"
else
  CMP_NAME="$REL_TAG"
  CMP_SHA="$(GLR --tags -- "$UPSTREAM" "refs/tags/$REL_TAG^{}" | awk 'NR==1{print $1}')"
  [[ -n "$CMP_SHA" ]] || CMP_SHA="$(GLR --tags -- "$UPSTREAM" "refs/tags/$REL_TAG" | awk 'NR==1{print $1}')"
  if [[ -z "$CMP_SHA" ]]; then
    printf '%s%s%s check-companion-freshness: could not resolve %s in %s despite listing it\n' \
      "$c_r" "$UX_ERR" "$c_0" "$REL_TAG" "$UPSTREAM" >&2
    exit 1
  fi
  [[ "$CMP_SHA" != "$SPLIT" ]] || current "with $UPSTREAM@$REL_TAG"

  # Not the release commit itself: current only if the release is an ANCESTOR of what is
  # vendored (a sync past the tag). Commits only, into a throwaway bare repo — the branch
  # plus every tag, since a lock can sit on either.
  TMPGIT="$(mktemp -d)" || {
    printf '%s%s%s check-companion-freshness: mktemp failed\n' "$c_r" "$UX_ERR" "$c_0" >&2
    exit 1
  }
  trap 'rm -rf "$TMPGIT"' EXIT
  git init -q --bare "$TMPGIT" || exit 1
  if ! GIT_TERMINAL_PROMPT=0 git -C "$TMPGIT" fetch -q --filter=tree:0 --tags -- "$UPSTREAM" "+$ref:refs/heads/upstream" 2>/dev/null; then
    skip "check-companion-freshness: could not fetch $UPSTREAM history to compare against $REL_TAG — offline/restricted?"
  fi
  if ! git -C "$TMPGIT" cat-file -e "$SPLIT^{commit}" 2>/dev/null; then
    # The vendored commit is on neither the branch nor any tag: the lock names something
    # upstream does not have (force-pushed away, or a typo). Not drift — a broken lock.
    printf '%s%s%s check-companion-freshness: companion_sha %s is not on %s@%s or any tag — companion.lock points at a commit upstream does not have\n' \
      "$c_r" "$UX_ERR" "$c_0" "${SPLIT:0:12}" "$UPSTREAM" "$BRANCH" >&2
    exit 1
  fi
  if git -C "$TMPGIT" merge-base --is-ancestor "$CMP_SHA" "$SPLIT"; then
    current "— $(git -C "$TMPGIT" rev-list --count "$CMP_SHA..$SPLIT") commit(s) past $REL_TAG, the latest htpx release"
  fi
fi

# Behind. Report the SHAs and how to update, then exit 2 (drift) so a scheduled run
# surfaces it as a nudge — distinct from the exit-1 hard failures above. The remediation
# is scripts/sync-companion.sh pinned to the release (which pulls htpx + bumps
# companion.lock), then the two manual follow-ups it can't do: eyeball the diff and
# drift-check the views.
if [[ -n "$REL_TAG" ]]; then SYNC="scripts/sync-companion.sh --ref $REL_TAG"; else SYNC="scripts/sync-companion.sh"; fi
{
  printf '%s%s%s vendored offensive/companion/ is behind %s@%s\n' "$c_y" "$UX_WARN" "$c_0" "$UPSTREAM" "$CMP_NAME"
  printf '    vendored: %s\n    upstream: %s\n' "${SPLIT:0:12}" "${CMP_SHA:0:12}"
  printf '    update:\n'
  printf '      %s\n' "$SYNC"
  printf '      git diff %s -- offensive/companion   # review the pulled change\n' "${SPLIT:0:12}"
  printf '      offensive/companion/gen-views.sh --check   # regenerate + commit if it reports drift\n'
} >&2
exit 2
