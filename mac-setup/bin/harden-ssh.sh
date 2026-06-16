#!/usr/bin/env bash
#
# harden-ssh.sh — Mac'in SSH'ını "sadece anahtar" yapar (parola girişini kapatır).
# İnternete açık (ngrok) erişimde brute-force saldırılarına karşı ana savunma budur.
#
#   sudo bash harden-ssh.sh
#
# ⚠️ ÖNEMLİ SIRA: Bunu çalıştırmadan ÖNCE, telefondaki ClaudeRemote uygulamasında
#    üretilen SSH genel anahtarını Mac'e eklemiş olmalısın:
#      mkdir -p ~/.ssh && echo "<uygulamadaki anahtar>" >> ~/.ssh/authorized_keys
#      chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
#    Aksi halde parolasız + anahtarsız kalıp SSH'tan kilitlenebilirsin!
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Bu script sudo ile çalışmalı:  sudo bash harden-ssh.sh"
  exit 1
fi

REAL_USER="${SUDO_USER:-$(whoami)}"
AUTH_KEYS="/Users/${REAL_USER}/.ssh/authorized_keys"

echo "==> Güvenlik ön kontrolü: anahtar eklenmiş mi?"
if [ ! -s "$AUTH_KEYS" ]; then
  echo "❌ DUR: $AUTH_KEYS yok veya boş."
  echo "   Önce uygulamadaki genel anahtarı ekle, sonra tekrar çalıştır."
  echo "   (Parolasız + anahtarsız kalırsan SSH'tan kilitlenirsin.)"
  exit 1
fi
echo "✅ authorized_keys bulundu ($(wc -l < "$AUTH_KEYS" | tr -d ' ') anahtar)."

DROPIN="/etc/ssh/sshd_config.d/100-clauderemote.conf"
echo "==> sshd sertleştirme yazılıyor: $DROPIN"

# sshd_config drop-in'leri include ediyor mu? Etmiyorsa ana dosyaya Include ekle.
if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
  cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
  printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> /etc/ssh/sshd_config
fi
mkdir -p /etc/ssh/sshd_config.d

cat > "$DROPIN" <<EOF
# ClaudeRemote güvenlik sertleştirmesi (internete açık SSH için maksimum koruma)

# --- Yalnızca açık anahtar; parola/etkileşimli giriş tamamen kapalı ---
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey
UsePAM no

# --- Yalnızca bu kullanıcı; root yasak ---
PermitRootLogin no
AllowUsers ${REAL_USER}

# --- Kaba-kuvvet yüzeyini daralt ---
MaxAuthTries 3
LoginGraceTime 20
MaxStartups 3:50:10
MaxSessions 4

# --- Ölü bağlantıları düşür ---
ClientAliveInterval 300
ClientAliveCountMax 2

# --- Mac'i bir sıçrama (pivot) noktası olarak kullanmayı engelle ---
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
X11Forwarding no
EOF

echo "==> Ayar sözdizimi doğrulanıyor (sshd -t)…"
if ! /usr/sbin/sshd -t; then
  echo "❌ sshd config testi başarısız; değişiklik geri alınıyor."
  rm -f "$DROPIN"
  exit 1
fi

echo "==> Remote Login yeniden başlatılıyor…"
launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || {
  echo "ℹ️  Otomatik reload olmadı; System Settings → Sharing → Remote Login'i KAPAT-AÇ yap."
}

echo ""
echo "✅ Bitti. Artık SSH yalnızca ANAHTAR ile giriş kabul eder (parola kapalı)."
echo "   Geri almak için:  sudo rm $DROPIN  ve Remote Login'i yeniden başlat."
