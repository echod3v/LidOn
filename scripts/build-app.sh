#!/bin/zsh
# LidOn.app 빌드 (유니버설: Apple Silicon + Intel)
#   scripts/build-app.sh                  → build/LidOn.app (ad-hoc 서명)
#   ARCHS=arm64 scripts/build-app.sh      → 현재 아키텍처만 (빠름)
#   SIGN_ID="Developer ID Application: …" scripts/build-app.sh  → 정식 서명
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-$(cat VERSION)}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
ARCHS=(${=ARCHS:-arm64 x86_64})
SIGN_ID=${SIGN_ID:--}

arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch $a); done

echo "▸ swift build (${ARCHS[*]})"
swift build -c release $arch_flags
BIN=$(swift build -c release $arch_flags --show-bin-path)

APP=build/LidOn.app
rm -rf build
mkdir -p $APP/Contents/{MacOS,Helpers,Resources}
cp $BIN/LidOnApp $APP/Contents/MacOS/LidOn
cp $BIN/LidOnCLI $APP/Contents/Helpers/lidon
cp Resources/AppIcon.icns $APP/Contents/Resources/
cp -R Resources/*.lproj $APP/Contents/Resources/
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" packaging/Info.plist > $APP/Contents/Info.plist
plutil -lint $APP/Contents/Info.plist >/dev/null

echo "▸ codesign ($SIGN_ID)"
sign_flags=(--force --sign "$SIGN_ID")
[[ "$SIGN_ID" != "-" ]] && sign_flags+=(--options runtime --timestamp)
codesign $sign_flags $APP/Contents/Helpers/lidon
codesign $sign_flags $APP
codesign --verify --strict $APP

echo "✓ $APP ($VERSION build $BUILD, $(lipo -archs $APP/Contents/MacOS/LidOn))"
