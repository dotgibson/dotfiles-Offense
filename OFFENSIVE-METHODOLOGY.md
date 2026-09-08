# Offensive Methodology — the TTP map behind the tool layer

This is the "why" for `offensive/offensive.zsh` and `install/offensive-packages.txt`:
how the tools line up against a real engagement and against **MITRE ATT&CK**, which
is the through-line the whole industry (and adversary-emulation tooling like
Caldera) organizes around. It's a reference, not a runbook — every step is gated
on **written authorization and a defined scope**.

> Looking for the concrete, copy-paste command syntax per service/port? That's
> the field reference in [`offensive/hacktheplanet`](offensive/hacktheplanet) —
> this doc is the map, that file is the commands. (Symlinked to `~/hacktheplanet`
> by `bootstrap.sh`; `htp` opens it.) Companion field references sit at the
> same altitude: [`offensive/exploitdev`](offensive/exploitdev) (`xdev`) for binary
> exploitation, and [`offensive/evasion`](offensive/evasion) (`evade`) for AV/AMSI/
> AppLocker evasion and breaching hardened defenses. One altitude *up* — the
> working **method** that decides which command you reach for and what to do when
> you're stuck (the "always be running recon" loop, shell stabilization, the
> scripted pseudo-shell) — is [`offensive/ippsec`](offensive/ippsec) (`ipp`),
> distilled from IppSec's HTB catalog. The defensive mirror — what each attack
> trips, as Splunk/Sentinel detections — is in [`PURPLE-TEAM.md`](PURPLE-TEAM.md).
>
> Rule zero: `mkengagement` writes `scope/scope.txt` *before* anything else and
> opens it in your editor. Fill it in first. Installing a tool is not permission
> to point it at anything.

---

## The phase → ATT&CK → tool map

| Phase                      | ATT&CK tactic(s)              | Go-to tools (this layer)                                                                                                        | Workspace dir               |
| -------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| **Recon**                  | Reconnaissance (TA0043)       | amass, subfinder, dnsx, bbot (`pipx`, not apt — see the 3.0 note below), theharvester, masscan                                  | `recon/`                    |
| **Scanning / enum**        | Discovery (TA0007)            | `nmapsweep`, nxc (smb/ldap/winrm), enum4linux-ng, ldapdomaindump (apt: python3-ldapdomaindump)                                  | `scans/`                    |
| **Initial access**         | Initial Access (TA0001)       | nuclei/httpx-toolkit/katana, ffuf/feroxbuster, sqlmap, Burp, responder                                                          | `web/`, `exploit/`          |
| **Cred access**            | Credential Access (TA0006)    | nxc, impacket (secretsdump), responder, hashcat/john, certipy-ad, sccmhunter (SCCM/MECM NAA + site takeover; upstream, not apt) | `loot/creds`, `loot/hashes` |
| **AD attack-path mapping** | Discovery / PrivEsc           | **`bhce`** → BloodHound CE, bloodhound-ce-python, SharpHound                                                                    | `loot/bloodhound`           |
| **Lateral movement**       | Lateral Movement (TA0008)     | nxc (exec over smb/winrm/mssql), impacket-psexec, evil-winrm                                                                    | `notes.md`                  |
| **Privilege escalation**   | Privilege Escalation (TA0004) | certipy-ad (AD CS), BloodHound paths, impacket                                                                                  | —                           |
| **C2 / persistence**       | Command & Control (TA0011)    | Sliver, AdaptixC2, Metasploit, Caldera (emulation); Havoc only if you already run it — upstream is archived                     | —                           |
| **Pivoting**               | Lateral Movement              | ligolo-ng, chisel, proxychains4, socat                                                                                          | —                           |
| **Reporting**              | —                             | your notes + `logshell` transcript                                                                                              | `report/`, `notes.md`       |

> **This table maps the on-prem network/AD engagement — that's the whole scope it
> claims.** Cloud/SaaS/identity (AWS, Entra, GCP, Okta, Snowflake), Kubernetes, and
> CI-CD supply chain (Jenkins, GitHub/GitLab runners, npm/PyPI, Terraform Cloud,
> Vault), plus the Impact tactic and the C2 tradecraft past the one row above, live in
> the **companion corpus** — `htpx` (`~/companion`), where each attack is paired with
> its detection. That material is **72 of the 106 red entries (68%) and 79 of the 105
> blue (75%)** — 151 of 211 overall — and none of it is projected into
> `hacktheplanet` or `PURPLE-TEAM.md`; the corpus is the map for it. (Counts are
> hand-maintained per `companion-sync`; both files carry the same caveat.)
> The CLIs those entries invoke are accounted for in
> [`install/offensive-packages.txt`](install/offensive-packages.txt).

### The one naming change that bites people

**CrackMapExec is gone — it's `nxc` (NetExec) now.** CME was archived in 2023; the
community fork NetExec is the maintained successor and the single highest-leverage
tool in the kit: SMB / LDAP / WinRM / MSSQL / RDP / FTP / SSH auth, enumeration,
lateral movement, credential extraction, *and* BloodHound collection — one
scriptable interface. The old `crackmapexec`/`cme` muscle memory just becomes `nxc`.

### bbot 3.0 moved the flags out from under 2.x muscle memory

**`-s` means `--seeds` now, not `--silent`** (silent moved to `-S`). That is the one
worth internalising, because it is the failure that does *not* announce itself: a 2.x
habit of `bbot -s` for quiet output now adds a **seed** — a new scan target — and
raises no error while doing it. On an engagement with a scoped target list, a flag you
typed for quiet is a flag that widened your scope.

The rest of the 3.0 break, in case a saved command line predates it: `--whitelist` is
retired (`-t/--targets` defines scope, `-s/--seeds` supplies the starting events),
`--allow-deadly` is gone, `noisy` was renamed `loud`, and six modules were removed
(wappalyzer, smuggler, digitorus, sitedossier, passivetotal, wpscan). Config and preset
values are pydantic-validated before a scan runs, so typos now fail fast instead of
silently doing nothing.

Nothing shipped in this repo breaks — bbot is named flagless in the table above, and no
corpus entry invokes it — so this is a note about **what you type from memory**, the
same exposure the wpscan 4.0 flag rename carries. bbot is `pipx`, not apt (it is in no
kali-rolling component), so upgrading is your call and your timing.

### BloodHound is now BloodHound CE

The legacy BloodHound 4.x collectors don't cleanly ingest into Community Edition.
Use a **CE-compatible collector** — the `bhce` helper drives nxc's `--bloodhound`
module, which packages a CE-ready zip into `loot/bloodhound/`. BloodHound CE itself
is a Postgres-backed web app, and on Kali it **is** an apt package now — `bloodhound`
(9.6.0-0kali1, migrated 2026-08-24) is Community Edition, not the legacy 4.x app the
name used to mean. It depends on neo4j/postgresql/curl and **not** on Docker, which is
the half that matters on WSL2: SpecterOps' `bloodhound-cli` stands up a compose stack,
so it wants Docker Desktop integration working first. `bloodhound-cli` (a Go binary —
curl the release or `go install`) is still the right route if you want the compose
stack or you're off Kali; it is no longer the only one.

---

## OPSEC / engagement hygiene baked into the layer

- **Scope first.** `scope/scope.txt` lists in-scope, out-of-scope, the auth
  reference, the time window, and an emergency "stop" contact. If it's blank,
  you're not ready to run.
- **Everything in `~/engagements`, never in the repo.** `$ENGAGEMENTS_DIR` lives
  outside any git tree; the Kali repo's paranoid `.gitignore` is only a backstop.
  Client data in a public showcase repo is a career-ender.
- **Audit trail.** `logshell` records a `script(1)` transcript into the
  engagement's `notes/` so you can reconstruct exactly what you ran and when —
  for the report and for deconfliction. `note "<text>"` adds timestamped
  observations to `notes.md` as you go (IppSec's note discipline — see
  [`offensive/ippsec`](offensive/ippsec)): capture every state change, cred, and
  host the instant it happens so the report writes itself.
- **WSL2 gotcha (already in PORTING-MATRIX).** A listener / reverse shell in Kali
  under WSL2 isn't reachable from your LAN until you set
  `networkingMode=mirrored` in the **Windows-side** `%UserProfile%\.wslconfig`
  (Win11 22H2+) — not `/etc/wsl.conf`. Bites every Sliver/Responder/C2 setup.

---

## What I deliberately did NOT put in the repo

- No payloads, implants, shellcode, or exploit code. Those are generated
  per-engagement, live in `exploit/` under `~/engagements`, and never sync.
- No target lists, creds, or loot. Same reason.
- No C2 server is vendored. Sliver, AdaptixC2 and Caldera are all apt packages now
  (so `up` carries them) — Caldera is no longer an install pointer, though it is in
  `kali-linux-large` and **not** `kali-linux-default`, so a default or slim box still
  needs its manifest line. Its slower release rhythm is not EOL: it moved from MITRE
  to the **Apache Incubator** (donated 2025-12-19, with the in-tree rebrand following
  Jul 2026; now `apache/caldera`, and `mitre/caldera` redirects), and that transition
  is the cadence. Configuring any of them is per-engagement work, and AdaptixC2's
  shipped defaults are fingerprinted, so treat "installed" as the starting line.

The dotfiles job is to make the **toolset and workspace** reproducible across
boxes. The tradecraft stays in your head and in the (private, out-of-repo)
engagement notes.
