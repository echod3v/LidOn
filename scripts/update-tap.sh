#!/bin/zsh
# 릴리스된 버전의 cask를 Homebrew tap(jayden0903/homebrew-tap)에 올린다: scripts/update-tap.sh 1.1.0
# (GitHub Actions가 릴리스를 만든 뒤 실행. gh 로그인 필요)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
V=${1:-$(cat VERSION)}
OWNER=${GITHUB_REPO%%/*}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
gh repo clone "$OWNER/homebrew-tap" "$TMP/tap" -- -q
gh release download "v$V" -R "$GITHUB_REPO" -p lidon.rb -D "$TMP" --clobber
mkdir -p "$TMP/tap/Casks" && cp "$TMP/lidon.rb" "$TMP/tap/Casks/lidon.rb"
cd "$TMP/tap"
if git diff --quiet; then echo "이미 최신이에요 ($V)"; exit 0; fi
git add Casks/lidon.rb && git commit -qm "lidon $V" && git push -q
echo "✓ $OWNER/homebrew-tap: lidon $V"
