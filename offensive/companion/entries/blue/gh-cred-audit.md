---
id: gh-cred-audit
title: Detect deploy-key / PAT credential backdoor (GitHub audit log)
detection: github-audit-log
event_ids: []
attack:
  tactic: TA0003
  techniques: [T1098]
source: GitHub post-compromise persistence (deploy key / PAT)
pair: gh-deploy-key-backdoor
---

Watch the credential-add invariants. A deploy key surfaces as `public_key.create`
(GitHub logs both deploy and account SSH-key adds under this action — prioritize the
writable, repo-bound ones; the event carries `read_only`, so `read_only=false` isolates
push-capable keys). A fine-grained PAT surfaces as
`personal_access_token.request_created` when it's requested, and
`personal_access_token.access_granted` when it's granted access to org resources
(admin approval, or immediately when the org doesn't require approval) — the grant is
the moment durable access is actually minted, so key on both. All three mint durable,
MFA-free access that survives a password reset, so an unexpected actor or an
out-of-band grant is the tell. Reconcile new credentials against known CI
integrations and review any created during an incident.

GitHub Enterprise audit-log telemetry, companion-only — `PURPLE-TEAM.md` is on-prem
Windows.

```spl
index=github sourcetype=github:audit action IN ("public_key.create", "personal_access_token.request_created", "personal_access_token.access_granted")
| table _time, actor, action, repo
```
