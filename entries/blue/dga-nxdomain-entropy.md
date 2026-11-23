---
id: dga-nxdomain-entropy
title: Detect DGA beacons (NXDOMAIN burst + label shape)
detection: splunk-spl
event_ids: [22]
attack:
  tactic: TA0011
  techniques: [T1568.002]
source: Sysmon DnsQuery (Event ID 22) + DNS resolver NXDOMAIN logs
pair: dga-c2-domains
---

A DGA host generates far more domains than register, so it leaves a trail of failed
resolutions from one `Image`/host in a short window. Two arms score that trail.
The **char-level** arm catches hex/base32/random-letter DGAs: a burst of NXDOMAIN
(or QueryStatus≠0) results whose labels are long and vowel-poor — a self-contained
proxy for the entropy a `dns_entropy` macro would score if you have one. High
fidelity; it's the arm the paired red trips. The **volume** arm drops the label-shape
test and alerts on a much larger count of *distinct* failed names alone, because
dictionary DGAs (word concatenation — Suppobox, Matsnu) produce pronounceable,
vowel-rich labels the vowel ratio is blind to, yet still miss en masse. It's lower
fidelity and overlaps telemetry, antivirus and CDN clients that probe many names —
baseline those out. Real dictionary-DGA coverage needs a word-list or n-gram
`lookup`, which this query doesn't ship. Sysmon 22 gives the process; the resolver's
NXDOMAIN log gives the failures — either alone works, together they're high fidelity.

```spl
index=sysmon EventCode=22 QueryStatus!=0
| eval label=mvindex(split(QueryName,"."),0), llen=len(label)
| eval vowels=llen-len(replace(lower(label),"[aeiou]","")), vowel_ratio=vowels/llen
| stats count as nxdomains, dc(QueryName) as uniq, avg(llen) as avg_len, avg(vowel_ratio) as avg_vowel by Image, host
| where (nxdomains>=40 AND avg_len>12 AND avg_vowel<0.3) OR uniq>200
| eval arm=if(avg_len>12 AND avg_vowel<0.3, "char-level", "volume")
| sort - nxdomains
```
