# Claude Code Terminal for iPhone

Use [Claude Code](https://docs.claude.com/en/docs/claude-code) (and any terminal program)
on your home Mac from your iPhone — even when you're away from home.

The phone is just a window: everything runs on the Mac. Your terminals stay alive on the
Mac inside `tmux`, so a dropped connection or a locked phone never kills your work.

> The iOS app is a SwiftUI SSH client built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
> (terminal rendering) and [Citadel](https://github.com/orlandos-nl/Citadel) (SSH). No third‑party
> account is required to use the app itself.

## How it works

```
[iPhone: the app]                         [Home Mac]
  SwiftTerm  (renders the terminal)         sshd (Remote Login, key-only)
  Citadel    (SSH client, Ed25519)  ──────▶ tmux  (sessions live here) + caffeinate
  Ed25519 key in Keychain (Face ID)         your shell / Claude Code / anything
```

Two hard problems and how they're solved:

- **Reaching a Mac behind a home router** → choose one: same Wi‑Fi (LAN), router port‑forwarding,
  or a zero‑config tunnel for carrier‑grade NAT (see *Connectivity* below).
- **Keeping work alive across drops** → `tmux` + `caffeinate`.

## Security

This exposes your Mac to the network, so security is treated as first‑class. See **[`SECURITY.md`](SECURITY.md)**
for the full threat model. In short:

- **Key‑only auth** (passwords disabled) → brute‑force is impossible.
- **Private key on the phone, behind Face ID**, never leaves the device; only the public key is on the Mac.
- **Trust‑on‑first‑use host‑key pinning** → a man‑in‑the‑middle / malicious relay can't impersonate your Mac.
- **App lock** (Face ID on launch & resume), **sshd hardening** (no root, single user, attempt limits, no
  forwarding/pivoting), and **shell‑quoted** remote commands.
- Run **`mac-setup/bin/claude-doctor`** to audit your Mac's posture before exposing it.

> Independent software, **not affiliated with Anthropic**.

## Requirements

- A Mac (kept awake / plugged in) with Xcode and Homebrew.
- An iPhone + a free Apple ID for signing (paid Apple Developer Program recommended for daily use,
  since free signing must be re‑installed every 7 days).
- `tmux` on the Mac: `brew install tmux`.

## Setup — Mac side

**One command** does the safe parts and prints the rest:

```bash
bash mac-setup/setup.sh
```

It installs the helper scripts to `~/bin`, installs `tmux` (+ `bore` for CGNAT), writes a
mobile‑friendly tmux config (touch scroll + big scrollback), checks Remote Login, and prints
your exact remaining steps — add your phone's key, harden SSH, set the login token, pick a
connectivity option. **Re‑run it anytime; it only fills in what's missing.** Keep the Mac
plugged in (the scripts use `caffeinate` so it won't sleep).

Prefer to do it by hand, or want to know exactly what each script does? See the full walkthrough
in [`mac-setup/SETUP.md`](mac-setup/SETUP.md).

## Setup — iOS app

```bash
cd ios-app
./build.sh             # build for the simulator (verifies the toolchain)
./install-device.sh    # build + install to a USB-connected iPhone (Developer Mode on)
```
Then in the app: **Add Mac** → choose **SSH Key** → copy the generated public key → add it to the
Mac's `~/.ssh/authorized_keys`. Connect, authenticate with Face ID, pick a session, and you're in.

> Building from the command line uses a couple of flags (see `build.sh`): a shared `SYMROOT` so the
> Swift package modules resolve against each other, and classic (non‑explicit) modules. Xcode's GUI
> usually doesn't need these.

## Connectivity

| Situation | Use | Host / Port in the app |
|-----------|-----|------------------------|
| Phone on the same Wi‑Fi | LAN | Mac's local IP (`ipconfig getifaddr en0`) · `22` |
| Public IP at home (no CGNAT) | Router port‑forward → Mac `:22` | your public IP · the forwarded port |
| Carrier‑grade NAT (private WAN IP like `10.x`) | A reverse tunnel (e.g. `bore`, `tailscale`, `cloudflared`) | the tunnel's host · port |

To check for CGNAT, compare your router's WAN IP with your public IP (`curl ifconfig.me`). If the
router's WAN IP is private (`10.x` / `100.64–127.x`), port‑forwarding won't work and you need a tunnel.
Because SSH is end‑to‑end encrypted and key‑only, routing it through a public tunnel relay stays safe —
the relay only carries encrypted bytes.

## Repository layout

| Path | Contents |
|------|----------|
| `ios-app/` | The SwiftUI app. `ClaudeRemote/` sources, `SSHKit/` (local SwiftPM package wrapping SwiftTerm + Citadel + SwiftNIO), `build.sh`, `install-device.sh`, `project.yml` (XcodeGen). |
| `mac-setup/` | Mac helper scripts and `SETUP.md`. No app on the Mac — just small scripts + settings. |

## License

MIT — see [`LICENSE`](LICENSE).
