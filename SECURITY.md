# Security model

This tool exposes a personal Mac's SSH to the network so a phone can drive it. That is powerful, so
security is treated as a first‑class concern. Read this before exposing your Mac to the internet.

> Run `mac-setup/bin/claude-doctor` on the Mac at any time to audit your posture.

## Threat model

The Mac becomes reachable over the network (LAN, a forwarded router port, or a public tunnel relay).
We assume an attacker who can reach the SSH port and may sit on the network path (a malicious tunnel
relay, hostile Wi‑Fi, or an on‑path attacker). We protect against:

| Threat | Defense |
|--------|---------|
| Password brute‑force / credential stuffing | **Key‑only auth** — `PasswordAuthentication no`, `AuthenticationMethods publickey`, `PermitEmptyPasswords no`. No password exists to guess. |
| Unauthorized login with a stolen key | Private key is **generated on the phone**, stored in the iOS **Keychain behind Face ID / Touch ID** (`.userPresence`, `ThisDeviceOnly`), and **never leaves the device**. Only the public key is on the Mac. |
| Man‑in‑the‑middle / malicious relay | **Trust‑on‑first‑use host‑key pinning.** The Mac's host key fingerprint is pinned on first connect; a changed key **refuses the connection** and warns the user. A relay therefore cannot impersonate the Mac. |
| Phone lost/stolen while unlocked | **App lock** — Face ID / passcode required on launch and when returning from background. The SSH key also requires Face ID. |
| Using the Mac as a pivot into the LAN | sshd hardening: `AllowTcpForwarding no`, `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`, `PermitTunnel no`, `GatewayPorts no`. |
| Privilege escalation via root login | `PermitRootLogin no`, `AllowUsers <you>` (only your account). |
| Command injection through session/chat names | All remote command arguments are shell‑quoted (`Shell.quote`). |
| Brute‑force amplification | `MaxAuthTries 3`, `LoginGraceTime 20`, `MaxStartups`, `MaxSessions`, dead‑connection reaping. |

## What the tunnel relay can and cannot see

When using a public tunnel (e.g. `bore.pub`) the relay forwards raw TCP. Because SSH is end‑to‑end
encrypted **and** the host key is pinned, the relay (or anyone on the path) carries only ciphertext and
**cannot** read your session or impersonate your Mac. For maximum control you can self‑host the relay.

## Residual risks (be honest)

- **Someone with your unlocked phone and your face/passcode** can connect. That is the trust boundary of
  any phone app. The app lock + key Face‑ID raise the bar but do not eliminate it.
- **A public tunnel endpoint is discoverable.** That's fine: key‑only auth means discovery ≠ access. Still,
  prefer LAN or port‑forwarding when you can, and rotate tunnels you don't need.
- **The Mac stays awake and reachable** while you use this. Turn off Remote Login / stop the tunnel when
  you're done if you want zero exposure.
- This is independent software and **not affiliated with Anthropic**.

## Hardening checklist

1. Add your phone's public key to `~/.ssh/authorized_keys` (perms `600`, `~/.ssh` `700`).
2. Run `sudo bash mac-setup/bin/harden-ssh.sh` (disables passwords, restricts users, limits attempts).
3. Run `mac-setup/bin/claude-doctor` — resolve every ✗ before exposing to the internet.
4. Keep the app lock enabled (Settings → App lock).
5. Prefer LAN / port‑forwarding over public relays when possible.

## Reporting

Found a vulnerability? Please open a private security advisory on the repository rather than a public issue.
