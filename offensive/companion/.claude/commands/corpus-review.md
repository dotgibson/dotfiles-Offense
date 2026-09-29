---
description: Judgment review of the htpx red↔blue corpus — ATT&CK correctness, pairing fidelity, red command correctness, coverage holes, detection quality (report-first)
argument-hint: "[tactic, platform, or detection-backend — optional, e.g. credential_access, aws, kql-entra-signin]"
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch, Bash(git ls-files:*), Bash(git log:*), Bash(wc:*)
---

# /corpus-review

Review the **quality and coverage** of the paired red↔blue corpus in
`entries/red/` and `entries/blue/` — the judgment half of the corpus gate.
`.github/workflows/ci.yml` already *enforces* the mechanical half on every change,
so this routine does **not** re-check what CI already proves. It reviews what an
awk script cannot: are the ATT&CK tags **correct**, does the red command actually
**run** what it claims, does a blue entry actually **detect** the red technique
it's paired with, and is the coverage honest.

The goal is a **reviewable report, not edits** — like every routine in this fleet,
report-first: propose, rank, and link; change nothing.

Focus for this run: **$ARGUMENTS** (empty = the whole corpus).

## Establish the denominator first — count it, never quote it

Before reading a single entry, compute the size of the corpus yourself:

```sh
git ls-files 'entries/red/*.md'  | wc -l      # RED  — total red entries
git ls-files 'entries/blue/*.md' | wc -l      # BLUE — total blue entries
```

Then count the **declared holes** — red entries carrying `pair: null` (Grep
`^pair: null` under `entries/red/`) — and derive `PAIRS = RED − holes`. That is the
identical walk `ci.yml`'s ATT&CK step performs (red drives it, `pair: null` is
skipped), so your `PAIRS` **must** equal the `ATT&CK tag agreement: N pairs checked`
line that step prints for this commit. If you cannot reconcile them, stop and report
the discrepancy as your lead finding — one of the two is wrong, and that matters more
than any entry-level defect you could find this cycle.

**Never take a count from prose.** Not from `README.md`, not from `CHANGELOG.md`, not
from a previous review issue. #124 read "105" off README's `## The Corpus` paragraph,
called it the whole corpus, and gave a clean bill to four entries added in `6b659bb`
that it had never opened — README had been stale since that commit. `ci.yml` now
asserts README's number against the computed pair count, so README *should* agree with
you: **cross-check it, and if it does not, that is a finding** — the gate is broken or
was bypassed. Adopt your own computed number either way.

Open the report with this header, verbatim in shape:

```text
Scope:    whole corpus | focus: <$ARGUMENTS>
Counted:  <RED> red, <BLUE> blue, <PAIRS> pairs (+ <holes> declared `pair: null`), at <short SHA>
Reviewed: <R> of <PAIRS> pairs read end to end
```

If `$ARGUMENTS` is non-empty, **or** `R < PAIRS` for any reason — time, a tool failure,
a slice you chose to skip — you reviewed a **SUBSET**. Say so in the first line and name
what you did not cover. "Whole corpus", "every entry", "all pairs" and "clean bill" are
reserved for a run where `R == PAIRS`. Using one otherwise is the worst failure this
routine can produce: it retires a risk nobody looked at.

### Entries added since the last review

The weekly beat means anything added in the last seven days has had no review at all.
Name them rather than trusting them to fall out of a full read:

```sh
git log --since='30 days ago' --diff-filter=A --name-only \
        --format='%h %ad %s' --date=short -- entries/red entries/blue
```

Every path that command prints gets its own line in the report — *reviewed, clean* /
*reviewed, finding below* / *not reviewed, because …*. A 30-day window, not 7, so a
skipped or failed run cannot open a gap. New pairs are the highest-risk content in the
corpus: least human attention, and exactly what #124 missed.

## Establish what CI already proves (do NOT re-litigate)

`ci.yml` mechanically enforces, on every push/PR, all of the following — treat them
as given and never report them as findings:

- **Bidirectional pairing integrity** — every entry with a non-`null` `pair:`
  resolves to a mate whose `pair:` points back. A broken pair is already a red X.
- **`{{slot}}` vocabulary conformance** — every `{{slot}}` used in any red entry is
  handled by the `htpx` browser script.
- **View drift** — `gen-views.sh --check` guarantees the generated blocks in the
  flat views match their entries.
- **Shell lint** — shellcheck + `bash -n` on the scripts.

CI green means the corpus is structurally sound and internally consistent. It does
**not** mean the entries are *correct security content*. That's this routine's job.

## What to review (the judgment CI can't do)

Read the entries first — the same list you counted above, in full unless you have
declared a SUBSET: `git ls-files 'entries/red/*.md' 'entries/blue/*.md'`. Each
red entry carries `attack: {tactic, techniques}`, `platform`, `pair`; each blue
entry carries `attack: {tactic, techniques}`, `detection`, `event_ids`, `pair`.

1. **ATT&CK validity.** For each `attack.tactic` (a `TA00xx` ID) and each
   `attack.techniques` entry (`Txxxx[.xxx]`), verify against **live MITRE ATT&CK**
   (attack.mitre.org) that the ID exists and is not **deprecated or renamed** — the
   framework moves and sub-techniques get renumbered. Don't trust memory. Flag
   invalid, deprecated, or superseded IDs with the current replacement.
2. **Red↔blue semantic fidelity — the highest-value dimension.** CI proves the
   `pair:` link exists; it cannot prove the blue entry actually detects the red
   one. For each pair, read both bodies: does the blue detection query/event set
   genuinely fire on the red technique's real telemetry? Flag pairs where the
   detection keys on an artifact the attack doesn't produce, misses the technique's
   actual signal, or is a generic catch-all masquerading as a targeted detection.
3. **Tactic ↔ technique coherence**, and **red-vs-blue `attack` agreement** within a
   pair (a red entry tagged `T1558.003` paired with a blue entry tagged `T1550.002`
   is a real mismatch — decide which is right).
4. **Coverage holes.** Which ATT&CK tactics or platforms (on-prem AD, Entra/M365,
   AWS, GCP, K8s, Okta, GWS, CI/CD, SaaS) are thin (one fragile pair) or absent
   relative to what the corpus claims to cover? Rank by how central the gap is, not
   by raw ATT&CK breadth. **`pair: null` is legitimate for a recon entry** (e.g.
   `entries/red/gcp-enum-recon.md`) — never flag an intentionally-unpaired recon entry
   as a missing pair.
5. **Detection quality / duplication.** Is a blue detection too broad (alert
   fatigue) or too brittle (trivially evaded)? Are two entries near-duplicates that
   should merge? Is a `source:` provenance stale or a claim unsupported — and does
   it credit **the toolkit the command actually shows**? (`device-code-phish`
   credited ROADtools for releases while running an AADInternals cmdlet.)
6. **Red command correctness — nothing else in this repo reads it.** Every red
   entry carries a fenced command block and no gate validates its contents: CI's
   checks are structural (pairing, slots, byte-drift, shell lint) and *projection is
   not the variable* — v2.8.1's `wmi-subscription` **was** projected and the
   byte-gate stayed green, because it asserts the flat view matches the entry, not
   that either names a real tool. So read the fence. For every binary invoked: does
   it **exist under that exact name** (a package's `Provides:` is not a binary —
   `proxychains` ships only as `proxychains4`), and is it the **right** one where a
   project has forked or renamed (`bloodhound-ce-python` vs legacy
   `bloodhound-python`, `netexec` vs `crackmapexec`)? Do the **flags and subcommands
   exist on that tool**, and does the invocation do what the prose claims? Does
   `platform:` match what the fence actually runs on — the same read settles it.
   Flag fabricated invocations, superseded binaries, and commands whose telemetry
   **cannot produce the signal the paired blue entry keys on** (a red line spraying
   Kerberos AS-REQ emits `4771`; a blue entry keying only on `4625` never fires).

   Two rules, both learned the hard way here:

   - **Do not guess a name.** You have no shell to test with — `command -v` and
     `apt-file` are not available to this routine and none of these tools are
     installed — so verify against the **upstream project, its docs, or a package
     index** via `WebSearch`/`WebFetch`, and cite what you checked. The v2.8.1
     review called `proxychains` "probably fine … one `command -v` settles it" and
     guessed the nxc module was an underscore typo; both guesses were wrong in the
     same direction: worse. If you cannot verify, say **needs-a-human-look** rather
     than proposing a replacement.
   - **Deleting can beat correcting.** `wmi-subscription`'s fabricated module was
     removed, not substituted — the nearest real thing would have made the entry
     describe a different technique. Propose deletion when no true equivalent exists.

## How to report

Open with the `Scope / Counted / Reviewed` header above — before anything else, every
run, including a no-findings one. Then a ranked shortlist, most-valuable first. For
each finding:

- **The entry/entries or gap** — exact path(s) under `entries/`, or the uncovered
  tactic/technique (with its verified ATT&CK ID).
- **Why it matters** — the concrete problem: *deprecated technique ID X → now Y*,
  *blue entry Z doesn't actually detect its paired attack*, *tactic W has no
  coverage*, *these two entries duplicate*.
- **The proposed change** — retag to this ID, tighten this detection, author a pair
  for this technique, merge these two. Concrete enough to act on, but **do not make
  the edit**.
- **Confidence** — high / needs-a-human-look, one line of rationale.

Lead with your single strongest finding. "The corpus is well-tagged, pairings are
faithful, and coverage matches the claim — no material gaps this cycle" is a valid,
useful result; say so plainly rather than manufacturing findings.
That verdict is available **only** to a run whose `Reviewed` equals `PAIRS`. On a
focused or partial run the honest form is "no material gaps in `<what you read>`",
scoped to the subset — never to "the corpus".

## If a finding is adopted

htpx is the **source of truth** for the corpus. A fix is an edit to `entries/`
here, then `./gen-views.sh` to refresh any local views and `ci.yml` to gate it; the
change fans out to `dotfiles-Offense`'s `offensive/companion/` via the existing
`auto-tag.yml` → `sync-fanout.yml` release path. Never hand-edit the vendored copy
in Offense. Propose only — do not edit entries unless asked.
