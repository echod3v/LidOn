#!/bin/bash
# LidOn 설치: curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_ID/LidOn/main/install.sh | bash
set -euo pipefail
REPO="${LIDON_REPO:-YOUR_GITHUB_ID/LidOn}"

echo "▸ Finding the latest LidOn release…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*LidOn-[^"]*\.zip"' | head -1 | cut -d'"' -f4)
[ -n "$URL" ] || { echo "Could not find a release for $REPO" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "▸ Downloading $URL"
curl -fL --progress-bar "$URL" -o "$TMP/LidOn.zip"
ditto -x -k "$TMP/LidOn.zip" "$TMP"

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
osascript -e 'quit app id "dev.lidon.LidOn"' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST/LidOn.app"
mv "$TMP/LidOn.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/LidOn.app" 2>/dev/null || true
echo "✓ Installed $DEST/LidOn.app"

CLI="$DEST/LidOn.app/Contents/Helpers/lidon"
for BIN in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [ -d "$BIN" ] && [ -w "$BIN" ]; then
    ln -sf "$CLI" "$BIN/lidon"
    echo "✓ Linked the lidon command → $BIN/lidon"
    break
  fi
done

open "$DEST/LidOn.app"
echo "✓ LidOn is running — look for the laptop icon in the menu bar."
