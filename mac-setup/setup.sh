#!/usr/bin/env bash
#
# setup.sh — one-command Mac setup for "Claude Code Terminal for iPhone".
#
# Safe to re-run (idempotent). It automates the boring parts (helper scripts,
# tmux, PATH, mobile tmux config) and CLEARLY prints the few steps that need
# your judgment (your phone's key, SSH hardening, the login token, connectivity).
#
# Usage:   bash mac-setup/setup.sh
#
set -euo pipefail
cd "$(dirname "$0")"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$1"; }
info() { printf '     %s\n' "$1"; }

# ── 1. Homebrew dependencies ────────────────────────────────────────────────
say "1/6  Dependencies (tmux, bore)"
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi
if command -v tmux >/dev/null 2>&1; then ok "tmux already installed"; else
  brew install tmux && ok "tmux installed"
fi
# bore: reverse tunnel for carrier-grade NAT (optional but common). Don't fail if unavailable.
if command -v bore >/dev/null 2>&1; then ok "bore already installed"; else
  brew install bore-cli 2>/dev/null && ok "bore installed" || warn "bore not installed (only needed for CGNAT; see step 6)"
fi

# ── 2. Helper scripts into ~/bin + PATH ─────────────────────────────────────
say "2/6  Helper scripts → ~/bin"
mkdir -p "$HOME/bin"
cp bin/claude-* bin/harden-ssh.sh bin/install-bore-service.sh "$HOME/bin/" 2>/dev/null || cp bin/* "$HOME/bin/"
chmod +x "$HOME"/bin/claude-* "$HOME"/bin/*.sh 2>/dev/null || true
ok "installed: claude-tmux, claude-sessions, claude-resume, claude-account, claude-doctor, harden-ssh.sh, …"
# Ensure ~/bin is on PATH for zsh (the macOS default shell).
if ! printf '%s' "${PATH:-}" | tr ':' '\n' | grep -qx "$HOME/bin"; then
  if [ -f "$HOME/.zshrc" ] && grep -q 'HOME/bin' "$HOME/.zshrc"; then :; else
    printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zshrc"
    warn "Added ~/bin to PATH in ~/.zshrc — open a new terminal (or 'source ~/.zshrc') to pick it up."
  fi
else
  ok "~/bin already on PATH"
fi

# ── 3. Mobile-friendly tmux config (touch scroll, big scrollback) ───────────
say "3/6  tmux config (touch scroll + scrollback)"
if [ -f "$HOME/.tmux.conf" ] && grep -q 'mouse on' "$HOME/.tmux.conf" 2>/dev/null; then
  ok "~/.tmux.conf already enables mouse mode"
elif [ -f "$HOME/.tmux.conf" ]; then
  warn "~/.tmux.conf exists. Add these lines for phone scrolling:"
  info "set -g mouse on"
  info "set -g history-limit 50000"
else
  cp tmux.conf.sample "$HOME/.tmux.conf" 2>/dev/null || printf 'set -g mouse on\nset -g history-limit 50000\n' > "$HOME/.tmux.conf"
  ok "wrote ~/.tmux.conf (mouse on, 50k scrollback)"
fi

# ── 4. Remote Login (SSH) ───────────────────────────────────────────────────
say "4/6  Remote Login (SSH)"
if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'on'; then
  ok "Remote Login already enabled"
else
  warn "Remote Login is OFF. Enable it with:"
  info "sudo systemsetup -setremotelogin on"
  info "(or System Settings → General → Sharing → Remote Login)"
fi

# ── 5. Claude login token (Keychain can't be read over SSH) ─────────────────
say "5/6  Claude login token"
if [ -d "$HOME/.config/claude-remote/accounts" ] && ls "$HOME/.config/claude-remote/accounts/"*.token >/dev/null 2>&1; then
  ok "account token(s) already configured ($(ls "$HOME/.config/claude-remote/accounts/" | sed 's/\.token//' | tr '\n' ' '))"
elif [ -f "$HOME/.config/claude-remote/env" ]; then
  ok "single-account token already configured"
else
  warn "No token yet. Claude's login lives in the macOS Keychain, which an SSH session can't read,"
  info "so remote sessions need a long-lived OAuth token (works with your subscription, NOT an API key):"
  info "claude setup-token            # run in the Mac GUI Terminal; copies an sk-ant-oat… token"
  info "claude-account add main       # paste it (repeat with another name for a 2nd account)"
fi

# ── 6. What you do next (needs your judgment) ───────────────────────────────
say "6/6  Final steps (do these yourself)"
info "a) In the iPhone app: Add Mac → SSH Key → copy the public key."
info "   On the Mac:  mkdir -p ~/.ssh && chmod 700 ~/.ssh"
info "                echo 'PASTE_PUBLIC_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
info "b) Lock SSH to key-only (AFTER the key works):  sudo bash ~/bin/harden-ssh.sh"
info "c) Audit posture anytime:                        claude-doctor"

# Connectivity hints. (We can't reliably detect CGNAT from the Mac — the Mac's own
# IP is always private — so we show your numbers and how to decide, without guessing.)
say "Connectivity"
DEF_IF="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
LAN_IP="$( [ -n "${DEF_IF:-}" ] && ipconfig getifaddr "$DEF_IF" 2>/dev/null || true )"
[ -z "${LAN_IP:-}" ] && LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
PUB_IP="$(curl -fs --max-time 4 ifconfig.me 2>/dev/null || true)"
[ -n "${LAN_IP:-}" ] && info "Same Wi-Fi:   connect the app to  $LAN_IP : 22"
[ -n "${PUB_IP:-}" ] && info "Public IP:    $PUB_IP"
info "Away from home: check your ROUTER's WAN IP (in its admin page) against the Public IP above."
info "  • They match & it's public → forward a router port to $LAN_IP:22, connect to Public IP."
info "  • WAN IP is private (10.x / 100.64–127.x) → carrier-grade NAT; port-forwarding can't work."
info "    Use a reverse tunnel:  bore local 22 --to bore.pub"
info "    Keep it always-on:     bash ~/bin/install-bore-service.sh"

say "Done. Re-run anytime — it only fills in what's missing."
