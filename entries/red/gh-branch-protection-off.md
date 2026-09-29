---
id: gh-branch-protection-off
title: Disable/override branch protection (merge unreviewed code)
section: GitHub / CI/CD
phase: Defense Impairment
attack:
  tactic: TA0112
  techniques: [T1685]
platform: [github]
source: GitHub supply-chain abuse (branch-protection tamper)
pair: gh-branch-protection-audit
---

Required reviews and status checks are the control that stops unreviewed code
reaching `main` (and the pipeline that deploys it). With admin, either delete the
rule outright, push, and (optionally) restore it — or leave it in place and use an
admin override to merge past it. Either path lands attacker code in the protected
branch; the first writes `protected_branch.destroy`, the second
`protected_branch.policy_override`. (Cloud CI — no slots.)

**ATT&CK note — `T1685` is the deliberate, least-bad fit (#133).**
Branch-protection tampering is a code-integrity / supply-chain control, not a
monitoring tool, but ATT&CK v19 revoked `T1562.001` into the `T1685` parent and no
TA0112 sub-technique fits more closely; the parent's "disrupt preventative
mechanisms" scope covers both deleting the rule and the admin policy override. Kept,
not swapped — unlike the 2FA pairs (#129 → `T1556.006`), TA0112 offers no clean
replacement here.

```sh
# delete protection on main, land code, then it can be re-created to cover tracks
gh api -X DELETE /repos/<owner>/<repo>/branches/main/protection
# — or, as admin, bypass the policy on a single merge (protected_branch.policy_override):
gh pr merge <pr-number> --admin --merge
```
