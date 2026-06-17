# Mac setup

No app runs on the Mac — just a few small scripts plus settings.

## Quick start (recommended)

From the repo root:

```bash
bash mac-setup/setup.sh
```

This automates steps 1–4 below (helper scripts, `tmux`/`bore`, PATH, mobile tmux config, Remote
Login check) and prints exactly what's left for you to do by hand (your phone's key, hardening,
the login token, connectivity). It's idempotent — safe to re-run; it only fills in what's missing.

The rest of this file is the **manual walkthrough / reference** for what that script does, step by step.

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

## 5. Remote login (macOS Keychain limitation)

Claude Code stores its login in the macOS **Keychain**, which a non‑GUI SSH session cannot read — over
SSH you'll see *"Not logged in"* even though the Mac's GUI is signed in. The fix is a **long‑lived OAuth
token**, which works with your existing **Claude subscription at no extra cost** (this is *not* an API key
— API keys bill per token):

```bash
# On the Mac GUI (Terminal), once:
claude setup-token            # sign in; prints a long-lived token (starts with sk-ant-oat...)

mkdir -p ~/.config/claude-remote
printf 'export CLAUDE_CODE_OAUTH_TOKEN="%s"\n' "PASTE_TOKEN_HERE" > ~/.config/claude-remote/env
chmod 600 ~/.config/claude-remote/env
```

`claude-tmux` and `claude-resume` source this file automatically, so **only your remote sessions** use the
token — local Mac usage is unchanged. The file is git‑ignored. If the token ever leaks, revoke it from the
Anthropic Console. (Viewing **past chats** does not need this — those are plain files on disk; the token is
only needed for Claude to actually talk to the model.)

### Multiple Claude accounts (optional)

If you use more than one Claude account, register each one and pick which to use from the app:

```bash
claude-account add work       # paste a setup-token for that account
claude-account add personal
claude-account list
```

Each account's token is stored separately (`~/.config/claude-remote/accounts/<name>.token`, `600`). In the
app's session list, an **Account** picker appears when more than one account exists; new terminals use the
selected account. Tokens are trimmed automatically (stray whitespace causes 401s).

## 6. Optional: push notifications

Subscribe to a private topic in the [ntfy](https://ntfy.sh) app, then:

```bash
mkdir -p ~/.config/claude-remote
printf 'NTFY_TOPIC="your-long-secret-topic"\n' > ~/.config/claude-remote/ntfy.conf
```

Wire `~/bin/claude-notify` into Claude Code's `Notification` / `Stop` hooks (see
`mac-setup/claude-hooks.settings.json` for an example block to merge into `~/.claude/settings.json`).
