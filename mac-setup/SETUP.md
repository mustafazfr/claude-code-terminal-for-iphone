# Mac setup

No app runs on the Mac — just a few small scripts plus settings. Run these from the repo root.

## 1. Install the helper scripts

```bash
mkdir -p ~/bin
cp mac-setup/bin/* ~/bin/
chmod +x ~/bin/claude-*
# make sure ~/bin is on your PATH (zsh):
grep -q 'HOME/bin' ~/.zshrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
brew install tmux
```

What they do:

| Script | Purpose |
|--------|---------|
| `claude-tmux [name]` | Attach to / create a persistent `tmux` session (wrapped in `caffeinate`). Does **not** auto‑start anything — you get a normal shell and stay in control. |
| `claude-sessions [n]` | List recent Claude Code conversations (`~/.claude/projects`), newest first. |
| `claude-resume <id> [cwd]` | Resume a past conversation in its project dir, inside a persistent tmux session. |
| `harden-ssh.sh` | Lock SSH down to key‑only (run with `sudo`, **after** adding your phone's key). |
| `claude-notify "msg"` | Optional: push a notification via [ntfy](https://ntfy.sh). |
| `claude-ngrok` | Optional: expose SSH via an ngrok TCP tunnel (needs an ngrok account). |

Optional, nicer mobile defaults for tmux:

```bash
cp mac-setup/tmux.conf.sample ~/.tmux.conf
```

Optional, see your Mac's local Terminal windows from the phone — make new terminals open inside
tmux automatically (only for local Terminal, never for SSH):

```sh
# add to ~/.zshrc
if command -v tmux &>/dev/null && [ -z "$TMUX" ] && [ -z "$SSH_CONNECTION" ] && [[ -o interactive ]]; then
  name="$(basename "$PWD" | tr -c 'A-Za-z0-9_-' '-')"; try="$name"; i=2
  while tmux has-session -t "=$try" 2>/dev/null; do try="${name}-${i}"; i=$((i+1)); done
  tmux new-session -s "$try" 2>/dev/null || true
fi
```

## 2. Enable Remote Login (SSH)

System Settings → General → Sharing → **Remote Login: On** (only your user), or:

```bash
sudo systemsetup -setremotelogin on
```

## 3. Add your phone's public key, then harden

In the app, add your Mac with **SSH Key** auth and copy the generated public key. Then on the Mac:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... clauderemote@iphone" >> ~/.ssh/authorized_keys   # paste your key
chmod 600 ~/.ssh/authorized_keys
sudo bash mac-setup/bin/harden-ssh.sh                                       # password login off
```

## 4. Reach the Mac from outside

Pick based on your network (see *Connectivity* in the top‑level README):

- **Same Wi‑Fi:** connect to the Mac's local IP (`ipconfig getifaddr en0`) on port `22`.
- **Public IP, no CGNAT:** forward an external port on your router to `<mac-local-ip>:22`.
- **Carrier‑grade NAT:** run a reverse tunnel, e.g. `bore local 22 --to bore.pub`, and connect to the
  host/port it prints.

## 5. Authentication note (macOS Keychain)

Claude Code stores its login token in the macOS **Keychain**, which a non‑GUI SSH session cannot read
(you'll see *"Not logged in"* over SSH even though the Mac GUI is signed in). For remote use, provide an
API key so SSH sessions authenticate without the Keychain:

```bash
mkdir -p ~/.config/claude-remote
printf 'export ANTHROPIC_API_KEY="%s"\n' "YOUR_API_KEY" > ~/.config/claude-remote/env
chmod 600 ~/.config/claude-remote/env
```

`claude-tmux` and `claude-resume` source this file automatically, so only your remote sessions use the
key — your local Mac usage is unchanged. (Get a key from the Anthropic Console. This file is git‑ignored.)

## 6. Optional: push notifications

Subscribe to a private topic in the [ntfy](https://ntfy.sh) app, then:

```bash
mkdir -p ~/.config/claude-remote
printf 'NTFY_TOPIC="your-long-secret-topic"\n' > ~/.config/claude-remote/ntfy.conf
```

Wire `~/bin/claude-notify` into Claude Code's `Notification` / `Stop` hooks (see
`mac-setup/claude-hooks.settings.json` for an example block to merge into `~/.claude/settings.json`).
