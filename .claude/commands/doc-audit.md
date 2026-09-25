---
description: Cross-check the offensive docs against the corpus, the package list, and the tree (report-first)
argument-hint: "[area, optional — e.g. hacktheplanet, packages, companion — defaults to full sweep]"
allowed-tools: Read, Grep, Glob, Bash(git ls-files:*), Bash(ls:*), Bash(./test/check-view-counts.sh:*)
---

# /doc-audit

Find **semantic drift** between the offensive docs and what the repo actually is —
the class of inconsistency the `companion.yml` byte-gate cannot catch, because it
only checks that the *generated* marker blocks match their entries, not the
hand-authored prose around them or the tooling the docs name. The red analog of
dotfiles-core's `/doc-audit`.

The goal is a **reviewable report, not edits** — report-first: flag, locate, propose;
change nothing.

Scope for this run: **$ARGUMENTS** (empty = full offensive-docs sweep).

## The read-only-corpus rule (know before you propose fixes)

`offensive/companion/` is a **vendored `git subtree` of dotgibson/htpx** — it is
read-only here. A corpus fix (an entry's content, tag, or pairing) must be made
**upstream in htpx**, not in this repo. What IS editable here: the hand-authored
prose in `offensive/hacktheplanet` and `PURPLE-TEAM.md` *outside* the
`companion:gen` markers, `install/offensive-packages.txt`, and `CLAUDE.md`. Route
each finding to the right place.

## What to check

Run these cross-checks (skip any out of the requested scope):

0. **Run the count gate first.** Execute `./test/check-view-counts.sh` (a read-only
   reporter — it never writes to the tree) and quote its exit status in the report. Exit 0
   means the hand-typed red/blue/projected counts the views state about the vendored corpus
   match the live tree — a tool-confirmed result, not a manual re-derivation. The semantic
   buckets it leaves as `-` slots (cloud/C2/Linux counts, the 68%/75% shares) still need
   your eye in the checks below.

1. **Corpus ↔ flat-view coverage.** The corpus (`offensive/companion/entries/red/`,
   `entries/blue/`) is far richer than what's projected into the flat views: only a
   fraction of red entries appear as `# companion:gen` blocks in
   `offensive/hacktheplanet`, and blue entries as `<!-- companion:gen -->` blocks in
   `PURPLE-TEAM.md`. Enumerate corpus entries that have **no** generated presence in
   the views — especially the cloud/SaaS/CI-CD slice (`aws-*`, `gcp-*`, `okta-*`,
   `k8s-*`, `npm-*`, `pypi-*`, `gh-*`, `gl-*`, `jenkins-*`, `vault-*`, `tfc-*`,
   `snowflake-*`, `harbor-*`, `slack-*`, `gws-*`, `cf-*`) — and judge which genuinely
   belong in the cheatsheet vs which are intentionally corpus-only. (Adding a view
   block is an htpx-side `gen-views.sh` change, then it syncs down.)
2. **Hand-authored commands ↔ corpus.** A command written directly in
   `hacktheplanet` (outside the markers) that **duplicates or contradicts** a corpus
   entry is silent drift the byte-gate can't see. Flag prose commands that restate a
   corpus technique differently (different flags, stale syntax) — the corpus is the
   source of truth for the paired slice.
3. **Docs ↔ `install/offensive-packages.txt`.** Tools named in `hacktheplanet` /
   `OFFENSIVE-METHODOLOGY.md` / `PURPLE-TEAM.md` that are **missing** from the package
   list (an operator following the docs won't have them), and listed packages that no
   doc references (dead weight or an undocumented capability). Cross-check binary
   renames (e.g. a doc invoking `crackmapexec` when the list moved to `netexec`/`nxc`).
4. **`CLAUDE.md` "Where things are" ↔ the tree.** The `offensive/` inventory in
   `CLAUDE.md` should match what's on disk (`git ls-files 'offensive/**'`). Flag files
   present but undocumented, documented but absent, or a moved path.
5. **`aliases.md` ↔ `offensive.zsh`** (if an `aliases.md` ships here) — documented
   offensive aliases/helpers that no longer exist, or notable helpers (`redup`,
   `ttyup`, `mkengagement`) missing from the cheatsheet.

## How to report

Group findings by severity, and **route each to the correct repo**:

- **Drift (fix needed)** — a concrete mismatch, with `file:line` on both sides and the
  one-line fix. Mark whether the fix lands **here** (view prose / packages / CLAUDE.md)
  or **upstream in htpx** (corpus entry).
- **Stale (likely outdated)** — probably wrong but needs your call.
- **Clean** — what was checked and matched, so a green run is trustworthy.

Lead with your single strongest finding. "The docs, corpus projection, and package
list are in step — no material drift this cycle" is a valid, useful result.

Do not edit anything unless explicitly asked. If asked: corpus fixes go **upstream in
htpx** (never the vendored `offensive/companion/`); view-prose, package, and
`CLAUDE.md` fixes land here.
