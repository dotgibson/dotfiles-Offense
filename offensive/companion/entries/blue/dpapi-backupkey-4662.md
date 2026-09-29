---
id: dpapi-backupkey-4662
title: Detect DPAPI backup-key theft (LSA secret read, 4662)
detection: splunk-spl
event_ids: [4662, 5145]
attack:
  tactic: TA0006
  techniques: [T1555]
source: Benjamin Delpy (mimikatz DPAPI) & Will Schroeder (SharpDPAPI), DPAPI research
pair: dpapi-backupkey
---

Detection posture: **narrow but real**. The domain backup key lives on the DC as
the LSA secrets `G$BCKUPKEY_PREFERRED` / `G$BCKUPKEY_P` / `G$BCKUPKEY_<guid>`.
Dumping it means reading those secret objects, and the read shows up as a `4662`
with `Object_Type=SecretObject`, `Access_Mask=0x2` and a `BCKUPKEY` object name.
That is the invariant. `impacket-dpapi backupkeys` and mimikatz
`lsadump::backupkeys` both call `LsarRetrievePrivateData` (MS-LSAD) over
`\pipe\lsarpc`, and neither touches MS-BKRP or `protected_storage`.

Don't key this on `lsarpc` `5145`. Every SID lookup on a DC opens that pipe, and it
is already one of the pipes `coercion-5145` sprays across. The `protected_storage`
`5145` stays in as a secondary signal for the other path: MS-BKRP `BackuprKey`
calls from tooling that asks the DC to decrypt a masterkey live, such as
`impacket-dpapi masterkey -t`. The *offline* decryption that follows either path
is invisible, so this read is the only on-wire moment.

This `4662` comes from `Object_Server=LSA`, not from the directory service, so it
logs under Object Access > Other Object Access Events. Enabling DS Access alone
won't produce it. (Needs Success auditing of the Other Object Access Events
subcategory on the DCs. The `5145` half needs detailed file-share auditing.) The
OTRF Security-Datasets recording of mimikatz `lsadump::backupkeys` against a DC,
which makes the same `LsarRetrievePrivateData` calls as impacket, shows one event
per secret read. That is about four per dump, each with
`Object_Name=Policy\Secrets\G$BCKUPKEY_*` and Accesses "Query secret value". The
same run's `5145`s are all `lsarpc`, with no `protected_storage`.

`4662` carries no source IP. To get it, join its `Logon_ID` to the matching
network-logon `4624`. Field names assume the classic `WinEventLog` sourcetype; on
`XmlWinEventLog` they are `ObjectServer` / `ObjectType` / `ObjectName` / `AccessMask`.

```spl
index=main (EventCode=4662 Object_Server="LSA" Object_Type="SecretObject" Access_Mask="0x2" Object_Name="*BCKUPKEY*")
    OR (EventCode=5145 Share_Name="*IPC$" Relative_Target_Name="protected_storage")
| table _time, host, EventCode, Account_Name, Logon_ID, Source_Address, Object_Name, Share_Name, Relative_Target_Name
```
