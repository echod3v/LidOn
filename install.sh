#!/bin/bash
# LidOn 설치: curl -fsSL https://raw.githubusercontent.com/jayden0903/LidOn/main/install.sh | bash
set -euo pipefail
REPO="${LIDON_REPO:-jayden0903/LidOn}"

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

# 한 번만: 뚜껑이 닫힌 채 충전기·모니터를 꽂거나 빼도 잠들지 않도록 (pmset disablesleep 두 명령만 허용)
if [ ! -e /etc/sudoers.d/lidon ]; then
  echo "▸ One-time setup: enter your Mac password so LidOn keeps running even if you plug in a charger"
  echo "  or display with the lid closed (allows only 'pmset -a disablesleep 0|1')."
  sudo "$CLI" system-setup --user "$USER" < /dev/tty || echo "  Skipped — you can finish this later from the LidOn menu or with: lidon system-setup"
fi

open "$DEST/LidOn.app"
echo "✓ LidOn is running — look for the laptop icon in the menu bar."
