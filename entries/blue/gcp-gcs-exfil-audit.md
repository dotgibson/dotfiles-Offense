---
id: gcp-gcs-exfil-audit
title: Detect GCS bulk exfil (GCP Data Access, storage.objects.get volume)
detection: gcp-logging
event_ids: []
attack:
  tactic: TA0009
  techniques: [T1530]
source: GCP Cloud Storage Data Access audit logs; object-read volume
pair: gcp-gcs-mass-exfil
---

The invariant is *volume from one principal*: a burst of `storage.objects.get` far
above that identity's baseline, usually preceded by a `storage.objects.list` sweep,
and weighted by a first-time principal↔bucket pairing, a new source IP, or a
server-side `storage.objects.rewrite` whose destination bucket is outside the org.
Alert on the per-principal object-read count over a short window rather than any
single read.

> Caveat: `storage.objects.get`/`list` are **Data Access** logs (`DATA_READ`), which
> are **off by default** and must be enabled per-service in the project/org IAM
> `auditConfigs` — the same telemetry gap that ships `gcp-enum-recon` unpaired. This
> detection only fires where GCS Data Access logging is turned on; where it is off,
> there is no read-level record, so fall back to structural controls — VPC Service
> Controls perimeters, least-privilege bucket IAM, and CMEK. And a server-side
> `rewrite` into an attacker bucket the org cannot see is a blind spot: catch that on
> the *source* object's `get`/`rewrite` read volume above, not on the destination.

GCP Cloud Audit Logs telemetry (native Cloud Logging filter below; also queryable as
Sentinel `GCPAuditLogs`), companion-only — `PURPLE-TEAM.md` is on-prem Windows.
Triage each hit by `protoPayload.authenticationInfo.principalEmail` (the actor) and
`protoPayload.resourceName` (the bucket/object touched); the read count and distinct
object names are the discriminator, so aggregate before you alert.

```text
logName=~"cloudaudit.googleapis.com%2Fdata_access"
protoPayload.serviceName="storage.googleapis.com"
protoPayload.methodName=("storage.objects.get" OR "storage.objects.list" OR "storage.objects.rewrite")
```
