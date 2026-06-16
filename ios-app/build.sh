#!/usr/bin/env bash
#
# ClaudeRemote'u iOS Simulator için üretip derler (doğrulama amaçlı).
# Cihaza kurmak için: Xcode'da aç (open ClaudeRemote.xcodeproj), takımını seç, Run.
#
# Bu ortamda gereken bayraklar (neden?):
#  - SYMROOT/OBJROOT (mutlak): standalone .xcodeproj'da xcodebuild paketleri
#    her checkout'un kendi build/ dizinine koyuyor → modüller birbirini göremiyor.
#    Mutlak, paylaşılan SYMROOT hepsini tek Products dizinine toplar.
#  - SWIFT/CLANG_ENABLE_EXPLICIT_MODULES=NO: "Explicitly Built Modules" bazı
#    ortamlarda C modülü .pcm'lerini bulamayıp derlemeyi bozuyor.
#  - ARCHS=arm64: tek mimari (Apple Silicon simülatörü) — hızlı.
#
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "xcodegen gerekli: brew install xcodegen"; exit 1; }

echo "==> xcodegen generate"
xcodegen generate

SYM="$PWD/SharedBuild"
echo "==> xcodebuild (iphonesimulator, arm64)"
xcodebuild -project ClaudeRemote.xcodeproj \
  -target ClaudeRemote -sdk iphonesimulator -configuration Debug \
  SYMROOT="$SYM" OBJROOT="$SYM/Intermediates" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO CLANG_ENABLE_EXPLICIT_MODULES=NO \
  "$@" build

echo ""
echo "✅ Derlendi: $SYM/Debug-iphonesimulator/ClaudeRemote.app"
echo "   Simülatörde çalıştırmak için:"
echo "     xcrun simctl boot 'iPhone 16' 2>/dev/null; open -a Simulator"
echo "     xcrun simctl install booted '$SYM/Debug-iphonesimulator/ClaudeRemote.app'"
echo "     xcrun simctl launch booted com.mustafa.clauderemote"
