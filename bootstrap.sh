#!/usr/bin/env bash
# dotfiles-Offense/bootstrap.sh
# Wire the OFFENSIVE (red) role layer onto an already-provisioned box.
# Distro-agnostic: installs NOTHING by default (your OS-native layer does that).
# Idempotent. Stacks: vendored Core + your OS-native layer + OFFENSIVE role.
#
# This repo used to be BOTH an OS-native layer for Kali and a role layer on top of it.
# The OS half now lives in dotfiles-Debian, which accepts ID=kali as a first-class
# target — so the apt base list, the SHA-pinned out-of-band installs, the WSL bootstrap
# and the ssh/git/zsh OS overlays all moved there. What is left here is the role.
#
# THE DRIVER FORM (dotgibson/dotfiles-core#976, #986). The shared half of a bootstrap —
# the flags, the Core symlink surface, the band-85 role stage, the managed ~/.zshrc
# loader, the closing report — is core/lib/bootstrap-lib.sh :: blib_main, ONE definition
# instead of a copy per repo. This file declares what it is (BOOTSTRAP_SU=lazy: escalation
# belongs to the opt-in installer, and only its apt route), defines the hooks that are
# genuinely offensive (the tool probe, the --install stack, the role's own links, the
# closing notes), and hands over. `--help` prints both halves.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Read by blib_main in the sourced lib (shellcheck does not follow into it).
# shellcheck disable=SC2034
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DO_CHECK=1
DO_INSTALL=0

# ── core/ subtree present? (inline: can't source a lib out of core/ before this) ─
# Validate the SPECIFIC paths we depend on (zsh modules + the two libs sourced next) so
# a missing/partial subtree fails HERE with a precise message, not later with a cryptic
# `source: No such file`.
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$_req" ]]; then
    echo "vendored core/ missing or incomplete (need $_req). To populate it:" >&2
    echo "  make sync          # in dotfiles-core — the fan-out that also stamps core.lock" >&2
    echo "If core/ does not exist AT ALL the fan-out skips this repo; do the one-time" >&2
    echo "vendor first, from a RELEASED TAG (never main, or core-integrity reports the" >&2
    echo "fresh tree as TAMPERED), then sync:" >&2
    echo "  git subtree add --prefix=core <dotfiles-core remote> refs/tags/v7 --squash" >&2
    exit 1
  fi
done
unset _req

# Shared bash UX palette + provisioning scaffold (vendored under core/lib).
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# ── what this repo is (read by blib_main) ─────────────────────────────────────
# shellcheck disable=SC2034
BOOTSTRAP_NAME="Offense"
# The band-85 role stage, tmux/role.conf and offensive/templates via blib_link_role_layer.
# NO BOOTSTRAP_OS, and no os/ directory at all any more: band 80 belongs to your OS-native
# repo (dotfiles-Debian, which covers Kali), not to this one.
# shellcheck disable=SC2034
BOOTSTRAP_ROLE=offensive
# Report-only by contract ("installs NOTHING by default"): blib_set_login_shell sudo's
# (chsh, /etc/shells), so the closing hook names the remedy (blib_login_shell_hint).
# shellcheck disable=SC2034
BOOTSTRAP_LOGIN_SHELL=0
# lazy: the driver resolves no escalator and primes no keepalive. Only --install escalates,
# and only on its Kali apt route — install_offensive does both itself at the point of need,
# so a plain run, a --links-only run and the pipx/go route never see a sudo prompt.
# shellcheck disable=SC2034
BOOTSTRAP_SU=lazy

# ── PATH prelude ──────────────────────────────────────────────────────────────
# bootstrap runs in BASH, before any of the zsh layer exists, so the user-local bindirs
# `--install` writes into are NOT on PATH yet — the OS layer's zsh fragment and Core's
# 00-tools.zsh only prepend them for the interactive shell. Without this every later
# `command -v <tool>` is blind to what an earlier step just installed, and the probe
# reports a tool it watched get installed as missing.
#   ~/.local/bin — pipx shims, and our GOBIN for the go installs
#   ~/.cargo/bin — cargo-installed tools an operator may have added
#
# Core's helper, NOT the hand-rolled `export PATH=` this used to be — which is also why it
# now sits BELOW the source line rather than above it. The literal list was a fork of
# core/lib/bootstrap-lib.sh :: blib_user_bindirs_on_path; the helper resolves CARGO_HOME
# and GOBIN/GOPATH instead of hard-coding ~/.cargo and ~/.local, so an operator who has
# moved either stops having their tools reported missing and reinstalled every run.
#
# audit-core.sh used to EXEMPT the role repos from this helper, on the reasoning that a
# role layer installs no packages. That was never true of this one — `--install` does pipx
# and `go install` into ~/.local/bin, which is exactly why the prelude was hand-rolled here
# in the first place — and the exemption is gone (dotgibson/dotfiles-core#748).
#
# `mkdir -p` FIRST, and that line is load-bearing rather than tidy. The helper adds only
# directories that EXIST — deliberately, so it cannot inject a bogus PATH entry — but the
# `export PATH=` this replaces added ~/.local/bin unconditionally. On a fresh box it does
# not exist until the first pipx or `go install` of this very run creates it, so a straight
# swap would silently DROP it for the whole run and the probe/report phase would go back to
# reporting a tool it watched get installed as missing — the exact failure the prelude was
# written for. Creating the directory we install into is a statement of intent, not a guess.
mkdir -p "$HOME/.local/bin" 2>/dev/null || true
# blib_main runs blib_user_bindirs_on_path right after this; _install_apt_absent calls it
# AGAIN, after pipx may have created ~/.cargo/bin or a GOBIN elsewhere. Idempotent.

# ── /etc/os-release, read once ────────────────────────────────────────────────
# NOT a gate. This bootstrap runs anywhere; the ID only decides which install ROUTE
# `--install` takes, and is reported by the probe so the report is interpretable.
OS_ID="" OS_ID_LIKE=""
if [[ -r /etc/os-release ]]; then
  OS_ID="$(sed -n 's/^ID=//p' /etc/os-release | head -1 | tr -d '"'"'"'')"
  OS_ID_LIKE="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | head -1 | tr -d '"'"'"'')"
fi
# Debian-family covers kali, debian, ubuntu, and anything declaring ID_LIKE=debian.
_is_debian_family() {
  case "$OS_ID" in kali | debian | ubuntu | raspbian) return 0 ;; esac
  case " $OS_ID_LIKE " in *" debian "*) return 0 ;; esac
  return 1
}

# ── hooks (called by blib_main, in its order; shellcheck cannot see that) ─────
# shellcheck disable=SC2329
bootstrap_usage() {
  cat <<'USAGE'
bootstrap.sh — wire the OFFENSIVE (red) role layer onto an already-provisioned box.
Distro-agnostic: installs NOTHING by default (your OS-native layer does that). Idempotent.

  --install       OPT-IN: also install the offensive tool stack (apt on Kali; a pipx/go
                  subset on other Debian-family boxes)
  --no-check      skip the host-tool probe
USAGE
}
# shellcheck disable=SC2329
bootstrap_flag() {
  case "$1" in
  --no-check) DO_CHECK=0 ;;
  --install) DO_INSTALL=1 ;;
  # Accepted, not an error: --no-offensive used to mean "skip the heavy tool install",
  # which is now the DEFAULT. Anyone (or any script) carrying the old flag should get
  # the behaviour they asked for, not an abort — so say it is redundant and move on.
  --no-offensive)
    echo "note: --no-offensive is redundant — this bootstrap installs nothing unless --install is passed" >&2
    ;;
  # Likewise --no-upgrade: there is no apt full-upgrade here any more. Your OS-native
  # layer owns that (dotfiles-Debian's bootstrap.sh, or plain `apt full-upgrade`).
  --no-upgrade)
    echo "note: --no-upgrade is obsolete — package upgrades belong to your OS-native layer" >&2
    ;;
  *) return 1 ;;
  esac
  return 0
}
# --links-only with --install is a contradiction rather than a preference, so it is
# refused instead of silently honouring one of the two. The driver has parsed both by now.
# shellcheck disable=SC2329
bootstrap_guard() {
  if ((BLIB_LINKS_ONLY && DO_INSTALL)); then
    echo "--links-only and --install contradict each other: one wires symlinks only, the other installs packages" >&2
    exit 1
  fi
}

# ── Host-tool probe (report only — never installs) ───────────────────────────
# `command -v` answers "is this on $PATH", which is NOT the question "is this tool on
# the box". Several offensive tools install somewhere $PATH never sees, and calling
# those "missing" sends you to reinstall something you already have. The opposite error
# would be just as wrong: offensive.zsh invokes these by bare name, so a tool that is
# present but off $PATH is still unusable by this layer. So report three states — on
# PATH, present-but-unreachable (with the one-line fix), and genuinely absent — and
# count only the last as missing. Same shape as dotfiles-Defense's probe.
#
# _probe_offpath <tool> — echo an executable path for <tool> found OFF $PATH, else fail.
# Deliberately a short, general list: tool-owned prefixes, unpacked release trees, snap,
# and pipx's venv bindir (how impacket/certipy/netexec arrive on a non-Kali box).
_probe_offpath() {
  local t="$1" p
  for p in "/opt/$t/bin/$t" "/usr/local/$t/bin/$t" "$HOME/.local/share/$t/$t" \
    "$HOME/.local/bin/$t" "/snap/bin/$t" "/usr/share/$t/$t"; do
    [ -x "$p" ] && {
      printf '%s\n' "$p"
      return 0
    }
  done
  return 1
}

# _probe_altname <tool> — echo an alternate command name for <tool> that IS on $PATH.
# One capability, several names depending on how it was packaged. This is the single
# biggest source of false "missing" on a non-Kali box: Kali ships wrapper scripts
# (impacket-secretsdump, httpx-toolkit, sliver-client) that pipx/go installs do not.
_probe_altname() {
  local t="$1" a
  case "$t" in
  impacket-secretsdump) set -- secretsdump.py ;;
  certipy-ad) set -- certipy ;;
  httpx-toolkit) set -- httpx ;;
  sliver-client) set -- sliver ;;
  searchsploit) set -- exploitdb ;;
  john) set -- john-the-ripper ;;
  # No bloodhound entry, deliberately: the CE collector installs as `bloodhound-ce-python`
  # from BOTH apt and pipx, so there is no alternate packaging name to teach. The legacy
  # `bloodhound-python` / `bloodhound.py` is a DIFFERENT capability — its zips don't ingest
  # into CE — so accepting it here would report a green tick for the one collector that
  # silently produces unusable output. A false "missing" is the cheaper failure.
  *) return 1 ;;
  esac
  for a in "$@"; do
    command -v "$a" >/dev/null 2>&1 && {
      printf '%s\n' "$a"
      return 0
    }
  done
  return 1
}

# _probe_list — the tools to probe, read from install/tools.lst (column 1, comments and
# blanks stripped). Single source: the set used to live only as a literal in this file,
# with nothing keeping it in step with what offensive.zsh actually calls.
_probe_list() {
  local f="$DOTFILES/install/tools.lst"
  [ -r "$f" ] || {
    blib_warn "install/tools.lst is missing or unreadable — cannot probe host tools"
    return 1
  }
  sed 's/#.*//' "$f" | awk 'NF { print $1 }'
}

check_tools() {
  blib_say "checking host tools on ${OS_ID:-an unknown distro} (install with --install, or via your OS layer)"
  local t missing=0 unreachable=0 found="" tools=""
  tools="$(_probe_list)" || return 0
  [ -n "$tools" ] || {
    blib_warn "install/tools.lst lists no tools — nothing probed"
    return 0
  }
  # Order is the file's order, and zsh leads it deliberately: it is the shell this whole
  # layer runs in, so its absence is categorically worse than a missing offensive tool.
  for t in $tools; do
    if command -v "$t" >/dev/null 2>&1; then
      blib_ok "found: $t"
    elif found="$(_probe_altname "$t")"; then
      blib_ok "found: $t (as \`$found\`)"
    elif found="$(_probe_offpath "$t")"; then
      blib_warn "unreachable: $t is installed at $found but is not on \$PATH"
      blib_warn "  offensive.zsh calls it by bare name — fix with:  ln -s $found ~/.local/bin/$t"
      unreachable=$((unreachable + 1))
    else
      blib_warn "missing: $t"
      missing=$((missing + 1))
    fi
  done
  # Wordlists are data, not commands, so `command -v` cannot see them — but the helpers
  # in offensive.zsh default straight at these paths, so their absence is worth one line.
  [ -d "${SECLISTS_DIR:-/usr/share/seclists}" ] ||
    blib_warn "seclists not at ${SECLISTS_DIR:-/usr/share/seclists} — set \$SECLISTS_DIR or install it"
  if ((missing == 0 && unreachable == 0)); then
    blib_ok "all probed tools present"
  else
    ((missing > 0)) &&
      blib_warn "$missing tool(s) missing — the offensive tools are optional; zsh is not"
    ((unreachable > 0)) &&
      blib_warn "$unreachable tool(s) installed but off \$PATH — symlink them (see above) or this layer cannot call them"
  fi
  # Report-only, like the rest of this probe: never a non-zero exit. Callers that want
  # to gate on it read the counts above.
  return 0
}

# The probe, unless --no-check (the driver already skips this hook under --links-only).
# Under --dry-run with --install, ALSO the installer's own preview: the driver never fakes
# bootstrap_provision on a dry run, and install_offensive's dry branches print what each
# route would do.
# shellcheck disable=SC2329
bootstrap_check() {
  if ((DO_CHECK)); then check_tools; fi
  if ((DO_INSTALL)) && [[ "${BLIB_DRY:-0}" != 0 ]]; then install_offensive; fi
}

# ── OPT-IN tool install (--install) ──────────────────────────────────────────
# Two routes, and the difference is not cosmetic.
#
#   Kali          → apt, from install/offensive-packages.txt. Kali packages essentially
#                   this entire stack, with the wrapper names offensive.zsh probes for.
#   other Debian  → a PORTABLE SUBSET via pipx + go. Debian and Ubuntu package almost
#                   none of it, so the alternative to this subset is nothing at all.
#   anything else → refuse, and say so. Guessing a package manager here would install
#                   the wrong thing under the right name.
#
# The subset is small ON PURPOSE. It is the set that (a) installs cleanly from PyPI or
# the Go module proxy with no system libraries to chase, and (b) offensive.zsh actually
# probes. Everything else — responder, evil-winrm, metasploit, hashcat, burp — has real
# packaging behind it and belongs to your OS layer or an upstream installer, not to a
# best-effort loop here.
#
# NAME MISMATCH, and it is deliberate rather than a bug to fix: pipx's impacket installs
# `secretsdump.py`, not Kali's `impacket-secretsdump` wrapper, and PyPI certipy-ad
# installs `certipy`, not `certipy-ad`. offensive.zsh probes the KALI names, so those
# HAVE_* flags will not fire on a pipx box. _probe_altname above teaches the report to
# recognise both, so at least the report tells the truth; making the shell layer resolve
# both names is a change to offensive.zsh, tracked separately.
apt_install() { # resilient: bulk first, then per-package (apt aborts on one bad name)
  local -a pkgs=("$@")
  if blib_priv apt-get install -y --no-install-recommends "${pkgs[@]}"; then return 0; fi
  blib_say "bulk install hit a snag — retrying package-by-package"
  local p
  for p in "${pkgs[@]}"; do
    # Keep --no-install-recommends on the retry too: without it the fallback path
    # quietly pulls a much larger dependency set than the bulk path would have, so
    # WHICH path ran changed what ended up on the box.
    blib_priv apt-get install -y --no-install-recommends "$p" ||
      blib_note_fail "package '$p' — unavailable on this box? check: apt-cache policy $p"
  done
}

# _pipx_install <pypi-name> <binary-it-provides>
# Guarded on the BINARY, not the package: that is what makes a re-run free, and it is
# the same question the probe asks. Best-effort — a failure here degrades the layer, it
# never aborts the wiring below.
_pipx_install() {
  local pkg="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    blib_ok "$bin already present — skipping"
    return 0
  fi
  blib_say "$pkg (pipx — provides $bin)"
  pipx install "$pkg" >/dev/null 2>&1 ||
    blib_note_fail "$bin — pipx install $pkg failed; retry by hand: pipx install $pkg"
}

# _go_install <module@version> <binary-it-provides>
# GOBIN is pinned to ~/.local/bin (already on PATH from the prelude) so the binaries land
# where the probe and the shell both look, rather than in a GOPATH the interactive shell
# may not export.
_go_install() {
  local mod="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    blib_ok "$bin already present — skipping"
    return 0
  fi
  blib_say "$bin (go install $mod)"
  GOBIN="$HOME/.local/bin" go install "$mod" >/dev/null 2>&1 ||
    blib_note_fail "$bin — go install $mod failed; retry by hand: GOBIN=\"\$HOME/.local/bin\" go install $mod"
}

# _install_apt_absent — the tools NO route can apt-install, on EVERY route.
#
# A THIRD category, and it does not obey the portable-subset rule above. That subset is
# "(a) installs cleanly from PyPI and (b) offensive.zsh actually probes", and it runs only
# on the non-Kali path because Kali packages everything in it. What lands here satisfies
# (a) and NOT (b): apt-absent corpus/doc tooling that offensive.zsh never calls, installed
# because nothing else on any route will install it.
#
# Called from BOTH branches of install_offensive on purpose. Hanging ROADtools off the
# non-Kali block would have installed it on every box EXCEPT the Kali/WSL2 attacker box
# this whole layer is built for — the one place dotfiles-Offense#231 wanted it.
#
# The bar for adding to this list is high, and sccmhunter is the worked example of failing
# it (dotfiles-Offense#230): not on PyPI at all, a `pipx install git+...` with a Python 3.13
# floor and an ldap3 fork pinned via [tool.uv.sources] that pip silently ignores. That is a
# best-effort loop that fails quietly, which is worse than the manifest's UPSTREAM note
# telling an operator to run one documented command. PyPI-clean, or it stays documented.
_install_apt_absent() {
  # Re-run the PATH prelude: the helper adds only directories that already EXIST, and on a
  # fresh box ~/.local/bin is created by the first pipx or go install of this very run.
  # Without this the guards below are blind to what this script just installed.
  blib_user_bindirs_on_path
  command -v pipx >/dev/null 2>&1 || {
    blib_warn "pipx not found — skipping the apt-absent tools (install pipx via your OS layer)"
    return 0
  }
  # ROADtools: roadrecon (Entra directory enum -> local DB + web UI) and roadtx (token
  # manipulation / auth flows, incl. the device-code flow). Two separate PyPI packages,
  # each with its own console_script of the same name. The corpus' Entra entries cite
  # dirkjanm's work and then hand you Windows-only PowerShell; this is the Linux half.
  _pipx_install roadrecon roadrecon
  _pipx_install roadtx roadtx
}

install_offensive() {
  local off_list="$DOTFILES/install/offensive-packages.txt"

  if [[ "$OS_ID" == kali ]]; then
    [[ -f "$off_list" ]] || {
      echo "missing $off_list — nothing to install" >&2
      return 1
    }
    local -a off=()
    mapfile -t off < <(blib_read_pkgs "$off_list")
    ((${#off[@]})) || {
      blib_warn "$off_list parsed to zero package names"
      return 0
    }
    if [[ "${BLIB_DRY:-0}" != 0 ]]; then
      blib_say "(dry run) would apt-install ${#off[@]} offensive packages (install/offensive-packages.txt)"
      blib_say "(dry run) would pipx-install (apt-absent, every route): roadrecon roadtx"
      return 0
    fi
    # Core's escalator and keepalive: resolve sudo/doas ONCE by absolute path (root runs
    # directly), prime it with the prompt visible, then refresh the timestamp in the
    # background. The one-shot `sudo -v` this replaces primed once and let it expire — on
    # a run whose next line says "go get coffee" — so the first sudo after the timeout
    # landed on a prompt nobody was watching. This branch owns the EXIT trap that stops
    # the refresher; the apt route is the only privileged thing this bootstrap does.
    blib_resolve_su --require || return 1
    trap 'blib_sudo_keepalive_stop' EXIT
    blib_sudo_keepalive_start || {
      echo "sudo authentication failed — cannot install packages" >&2
      return 1
    }
    export DEBIAN_FRONTEND=noninteractive
    blib_say "apt update (the offensive stack is heavy — go get coffee)"
    blib_priv apt-get update
    apt_install "${off[@]}"
    blib_sudo_keepalive_stop
    blib_ok "offensive packages requested: ${#off[@]}"
    blib_say "the apt list is Kali's. On a slim box some of these ship in kali-linux-default already."
    # Kali packages nearly this whole stack, but not ROADtools — and apt is the ONLY thing
    # this branch used to run, so the Entra half stayed missing on the very box that needs it.
    _install_apt_absent
    return 0
  fi

  if ! _is_debian_family; then
    blib_warn "--install has no route for ${OS_ID:-this distro}"
    blib_warn "  the apt list is Kali's and the portable subset assumes a Debian-family box."
    blib_warn "  install the tools your OS packages, then re-run without --install to see the report."
    return 0
  fi

  # Portable subset: Debian/Ubuntu (and any other ID_LIKE=debian box) that is not Kali.
  blib_say "not Kali (ID=${OS_ID:-unknown}) — installing the PORTABLE SUBSET only"
  blib_say "  the rest of install/offensive-packages.txt is Kali-packaged; see its UPSTREAM notes"
  if [[ "${BLIB_DRY:-0}" != 0 ]]; then
    blib_say "(dry run) would pipx-install: impacket certipy-ad netexec bloodyAD ldapdomaindump bloodhound-ce"
    blib_say "(dry run) would pipx-install (apt-absent, every route): roadrecon roadtx"
    blib_say "(dry run) would go-install:   nuclei gobuster ffuf kerbrute"
    return 0
  fi

  if command -v pipx >/dev/null 2>&1; then
    # Binary names are the ones the tool actually installs, which for impacket and
    # certipy-ad are NOT the Kali wrapper names — see the block comment above.
    _pipx_install impacket secretsdump.py
    _pipx_install certipy-ad certipy
    _pipx_install netexec nxc
    _pipx_install bloodyAD bloodyAD
    _pipx_install ldapdomaindump ldapdomaindump
    # PyPI `bloodhound-ce` provides the same `bloodhound-ce-python` binary Kali's package does.
    # Without it a non-Kali box got no collector at all, while tools.lst probed for one — a
    # warning that could never be satisfied by --install.
    _pipx_install bloodhound-ce bloodhound-ce-python
  else
    blib_warn "pipx not found — skipping the python tools (install pipx via your OS layer)"
  fi

  # Apt-absent on this route too — it is apt-absent on EVERY route, which is the point.
  _install_apt_absent

  if command -v go >/dev/null 2>&1; then
    _go_install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest nuclei
    _go_install github.com/OJ/gobuster/v3@latest gobuster
    _go_install github.com/ffuf/ffuf/v2@latest ffuf
    # kerbrute is upstream-FROZEN (last release v1.0.3, Dec 2019) and has never been
    # apt-packaged, so @latest here is a stable commit rather than a moving target —
    # which is exactly why redup does not carry it as a "fast mover".
    _go_install github.com/ropnop/kerbrute@latest kerbrute
  else
    blib_warn "go not found — skipping the go tools (install golang via your OS layer)"
  fi
}

# Opt-in, and lazy about privilege: install_offensive resolves the escalator and runs the
# keepalive itself, on the one route that needs them.
# shellcheck disable=SC2329
bootstrap_provision() {
  if ((DO_INSTALL)); then install_offensive; fi
}

# Links only this repo owns, after Core and the role layer and BEFORE the managed ~/.zshrc
# is written: the pre-role-layer migration, the `prefix + e` popup script, the field
# references surfaced at ~/.
# shellcheck disable=SC2329
bootstrap_wire_pre_loader() {
  # ── migrate a box bootstrapped before the role layer existed ───────────────
  # Two destinations this repo used to write are no longer ours, and both are left
  # DANGLING by the change above rather than updated:
  #
  #   $CONFIG/tmux/os.conf        — was os/kali.conf; the OS repo owns band 80 now
  #   $CONFIG/kali/templates      — templates moved to $CONFIG/offensive/templates
  #
  # Remove each ONLY when it is a symlink resolving inside THIS checkout. That guard is
  # the whole point: on a box also running dotfiles-Debian, $CONFIG/tmux/os.conf is
  # Debian's live link and must not be touched. Core deliberately declined a compat
  # symlink for the templates move (it would preserve a ~/.config/kali/ on a repo no
  # longer called Kali), so cleaning up is the alternative to leaving one behind.
  local _stale
  for _stale in "$CONFIG/tmux/os.conf" "$CONFIG/kali/templates"; do
    [[ -L "$_stale" ]] || continue
    # `readlink`, NOT `readlink -f`. -f CANONICALISES, which requires every parent
    # component of the target to exist — and os/ has just been deleted, so -f returns
    # EMPTY for exactly the dangling link this loop exists to clear, and the guard below
    # would never match it. Plain readlink reads the stored target verbatim, dangling or
    # not, which is the question being asked: does this link point into THIS checkout?
    [[ "$(readlink "$_stale" 2>/dev/null)" == "$DOTFILES"/* ]] || continue
    if [[ "${BLIB_DRY:-0}" != 0 ]]; then
      blib_say "would drop stale link from the pre-role-layer wiring: $_stale"
    else
      rm -f "$_stale"
      # Take the now-empty $CONFIG/kali with it; rmdir refuses a non-empty dir, so a
      # host that put something else there keeps it.
      rmdir "${_stale%/*}" 2>/dev/null || true
    fi
  done

  # The `prefix + e` popup script. It CANNOT live under $CONFIG/tmux/scripts — that path
  # is a whole-dir symlink to core/tmux/scripts (Core-owned, no offensive script) — so
  # link it a level up, beside tmux.conf, and the binding points there. Gated on
  # `blib_want tmux` so --skip tmux / --only … behave consistently with Core's own wiring.
  blib_want tmux && [[ -f "$DOTFILES/offensive/tmux/tmux-eng.sh" ]] && blib_link "$DOTFILES/offensive/tmux/tmux-eng.sh" "$CONFIG/tmux/tmux-eng.sh"

  # CTF/HTB cheatsheet + companion field references — surfaced at ~/ for htp/xdev/evade/ipp.
  [[ -f "$DOTFILES/offensive/hacktheplanet" ]] && blib_link "$DOTFILES/offensive/hacktheplanet" "$HOME/hacktheplanet"
  [[ -f "$DOTFILES/offensive/exploitdev" ]] && blib_link "$DOTFILES/offensive/exploitdev" "$HOME/exploitdev"
  [[ -f "$DOTFILES/offensive/evasion" ]] && blib_link "$DOTFILES/offensive/evasion" "$HOME/evasion"
  [[ -f "$DOTFILES/offensive/ippsec" ]] && blib_link "$DOTFILES/offensive/ippsec" "$HOME/ippsec"
  # The structured red<->blue companion (the `htpx` browser + its entries/ tree).
  # Linked as a directory so htpx resolves entries/ relative to itself; run via `htpx`.
  [[ -d "$DOTFILES/offensive/companion" ]] && blib_link "$DOTFILES/offensive/companion" "$HOME/companion"

  # The `prefix + e` popup script. It CANNOT live under $CONFIG/tmux/scripts — that path
  # is a whole-dir symlink to core/tmux/scripts (Core-owned, no offensive script) — so
  # link it a level up, beside tmux.conf, and the binding points there. Gated on
  # `blib_want tmux` so --skip tmux / --only … behave consistently with Core's own wiring.
  blib_want tmux && [[ -f "$DOTFILES/offensive/tmux/tmux-eng.sh" ]] && blib_link "$DOTFILES/offensive/tmux/tmux-eng.sh" "$CONFIG/tmux/tmux-eng.sh"

  # CTF/HTB cheatsheet + companion field references — surfaced at ~/ for htp/xdev/evade/ipp.
  [[ -f "$DOTFILES/offensive/hacktheplanet" ]] && blib_link "$DOTFILES/offensive/hacktheplanet" "$HOME/hacktheplanet"
  [[ -f "$DOTFILES/offensive/exploitdev" ]] && blib_link "$DOTFILES/offensive/exploitdev" "$HOME/exploitdev"
  [[ -f "$DOTFILES/offensive/evasion" ]] && blib_link "$DOTFILES/offensive/evasion" "$HOME/evasion"
  [[ -f "$DOTFILES/offensive/ippsec" ]] && blib_link "$DOTFILES/offensive/ippsec" "$HOME/ippsec"
  # The structured red<->blue companion (the `htpx` browser + its entries/ tree).
  # Linked as a directory so htpx resolves entries/ relative to itself; run via `htpx`.
  [[ -d "$DOTFILES/offensive/companion" ]] && blib_link "$DOTFILES/offensive/companion" "$HOME/companion"
  return 0
}

# What only this repo knows at the end. blib_login_shell_hint is the report-only guard
# (returns non-zero when zsh is absent — the wiring is inert — so the driver prints no
# "complete" line; sets the closing hint to "for this session: exec zsh" when zsh is
# present but not the login shell).
# shellcheck disable=SC2329
bootstrap_closing() {
  blib_say "engagement data lives in ~/engagements (outside this repo) — run \`mkengagement <name>\` to start one"
  blib_login_shell_hint
}

blib_main "$@"
