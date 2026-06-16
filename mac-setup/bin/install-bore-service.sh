#!/usr/bin/env bash
#
# install-bore-service.sh <port>
#
# bore tünelini kalıcı bir LaunchAgent'a çevirir: Mac açılışında otomatik başlar,
# çökerse/koparsa kendini yeniden başlatır (KeepAlive), Mac uyumaz (caffeinate).
# Böylece "evdeyken Mac'i açık tut, gerisi otomatik" olur.
#
#   bash install-bore-service.sh 40022
#   (durdurmak için:  launchctl unload ~/Library/LaunchAgents/com.clauderemote.bore.plist)
#
set -euo pipefail

PORT="${1:-${BORE_PORT:-}}"
if [ -z "$PORT" ]; then
  echo "Kullanım: bash install-bore-service.sh <port>   (örn. 40022)"
  exit 1
fi

BORE="$(command -v bore 2>/dev/null || echo /opt/homebrew/bin/bore)"
[ -x "$BORE" ] || { echo "❌ bore bulunamadı. Kur: brew install bore-cli"; exit 1; }

LABEL="com.clauderemote.bore"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.config/claude-remote/bore.log"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.config/claude-remote"

# Elle başlatılmış bore örneklerini durdur (çakışma olmasın).
pkill -f "bore local 22" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-dis</string>
    <string>${BORE}</string>
    <string>local</string>
    <string>22</string>
    <string>--to</string>
    <string>bore.pub</string>
    <string>--port</string>
    <string>${PORT}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${LOG}</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✅ bore servisi kuruldu (port ${PORT}). Mac açılışında otomatik başlar, koparsa yeniden bağlanır."
echo "   Adres:  bore.pub:${PORT}"
echo "   Log:    ${LOG}"
echo "   Durdur: launchctl unload ${PLIST}"
