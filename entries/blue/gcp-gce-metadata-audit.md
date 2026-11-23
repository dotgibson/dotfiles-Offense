---
id: gcp-gce-metadata-audit
title: Detect GCE metadata exec (GCP audit, setMetadata startup-script + reset)
detection: gcp-logging
event_ids: []
attack:
  tactic: TA0002
  techniques: [T1651]
source: GCP Compute Admin Activity audit logs; setMetadata / reset
pair: gcp-gce-startup-script-exec
---

The invariant is a **control-plane metadata write that changes a startup key**,
corroborated by the boot that runs it — and the query has to catch both, because
`setMetadata` alone is noisy (labels, ssh-keys, and app config all ride the same
call) while a `reset` alone is benign. So key on `v1.compute.instances.setMetadata`
and read the `request.metadata` delta for a `startup-script`, `startup-script-url`,
or the Windows `windows-startup-script-*` keys — those are the exec-bearing ones —
then treat a `v1.compute.instances.reset` from the *same* `principalEmail` against the
*same* instance inside a short window as the confirming second arm.

Do not narrow to a single key literal: the plural set above are **different keys**, so
enumerate them rather than substring-matching `startup` (the payload can also arrive
by URL, where the script bytes never appear in the log at all — the key name is your
only signal, which is exactly why the key-name match cannot be skipped).

GCP Cloud Audit Logs telemetry (native Cloud Logging filter below; also queryable as
Sentinel `GCPAuditLogs`), companion-only — `PURPLE-TEAM.md` is on-prem Windows. Unlike
the Data Access half of GCP, Admin Activity logs are **always-on and immutable**, so
`setMetadata`/`reset` are recorded with no telemetry-off caveat. Triage by
`protoPayload.authenticationInfo.principalEmail` (the actor) and
`protoPayload.resourceName` (the instance), and confirm the changed key in
`protoPayload.request` on the hit.

```text
logName=~"cloudaudit.googleapis.com%2Factivity"
protoPayload.serviceName="compute.googleapis.com"
(protoPayload.methodName=~"compute.instances.setMetadata$"
 OR protoPayload.methodName=~"compute.instances.reset$")
```
