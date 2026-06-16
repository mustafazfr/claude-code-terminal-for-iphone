#!/usr/bin/env bash
#
# ClaudeRemote'u USB ile bağlı iPhone'a derleyip kurar (imzalı).
#
# Gerekli:
#  - iPhone USB ile bağlı, "güven" verilmiş, eşleştirilmiş.
#  - iPhone'da Developer Mode açık (Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu).
#  - Xcode'da Apple ID ile giriş yapılmış (otomatik imza için).
#  - Farklı bir takım için: DEVELOPMENT_TEAM=XXXX ./install-device.sh
#
set -euo pipefail
cd "$(dirname "$0")"

# Apple takım kimliğini kendi imzalama sertifikandan otomatik algıla
# (DEVELOPMENT_TEAM ile elle de geçebilirsin).
TEAM="${DEVELOPMENT_TEAM:-$(security find-certificate -a -c 'Apple Development' -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]+' | head -1 | cut -d= -f2)}"
if [ -z "$TEAM" ]; then
  echo "❌ Apple takımı bulunamadı. Xcode'da bir kez giriş yap (Settings → Accounts),"
  echo "   ya da DEVELOPMENT_TEAM=XXXX ./install-device.sh ile geç."
  exit 1
fi

command -v xcodegen >/dev/null || { echo "xcodegen gerekli: brew install xcodegen"; exit 1; }
echo "==> xcodegen generate"
xcodegen generate >/dev/null

# Bağlı cihazın xcodebuild hedef id'si (donanım UDID) — Simulator olmayan iOS satırı:
HWID=$(xcodebuild -project ClaudeRemote.xcodeproj -scheme ClaudeRemote -showdestinations 2>/dev/null \
  | grep -E "platform:iOS, arch:arm64, id:" | grep -v Simulator | head -1 \
  | sed -E 's/.*id:([0-9A-Fa-f-]+).*/\1/')

# devicectl install için CoreDevice kimliği (UUID):
COREID=$(xcrun devicectl list devices 2>/dev/null \
  | grep -iE "available|connected" \
  | grep -oiE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)

if [ -z "$HWID" ]; then
  echo "❌ Bağlı geliştirme cihazı bulunamadı."
  echo "   iPhone'u USB ile bağla, 'Bu bilgisayara güven' de, Developer Mode'u aç."
  exit 1
fi
echo "   Cihaz UDID (build):   $HWID"
echo "   Cihaz id  (install):  ${COREID:-<bulunamadı, varsayılan kullanılacak>}"

DDP="$PWD/DerivedDataDevice"
echo "==> xcodebuild (imzalı, iphoneos)"
xcodebuild -project ClaudeRemote.xcodeproj -scheme ClaudeRemote \
  -destination "id=$HWID" -derivedDataPath "$DDP" -allowProvisioningUpdates \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES DEVELOPMENT_TEAM="$TEAM" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO CLANG_ENABLE_EXPLICIT_MODULES=NO build

APP="$DDP/Build/Products/Debug-iphoneos/ClaudeRemote.app"
echo "==> kurulum"
if [ -n "$COREID" ]; then
  xcrun devicectl device install app --device "$COREID" "$APP"
else
  xcrun devicectl device install app "$APP"
fi

echo ""
echo "✅ Kuruldu. İlk açılışta imza hatası alırsan:"
echo "   iPhone → Ayarlar → Genel → VPN ve Cihaz Yönetimi → geliştirici uygulamasına GÜVEN."
echo "   (Ücretsiz Apple hesabında uygulama 7 günde bir bu script'le yeniden kurulmalı.)"
