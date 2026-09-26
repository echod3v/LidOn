#!/bin/zsh
# 앱 아이콘 생성: 앱 안의 맥북 뷰를 그대로 렌더링한다 → Resources/AppIcon.icns, Resources/AppIcon.png
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product LidOnApp >/dev/null
BIN=$(swift build -c release --show-bin-path)/LidOnApp
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
"$BIN" --render-icon "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  sips -z ${spec%%:*} ${spec%%:*} "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${spec#*:}.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
sips -z 512 512 "$TMP/icon.png" --out Resources/AppIcon.png >/dev/null
echo "✓ Resources/AppIcon.icns, Resources/AppIcon.png"
