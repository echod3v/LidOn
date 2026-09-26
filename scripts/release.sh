#!/bin/zsh
# 릴리스 zip + Homebrew cask 생성: scripts/release.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

V=${1:?usage: scripts/release.sh <version>}
echo "$V" > VERSION
swift test
python3 scripts/check-l10n.py
VERSION=$V scripts/build-app.sh

mkdir -p dist
ZIP=dist/LidOn-$V.zip
rm -f $ZIP
ditto -c -k --sequesterRsrc --keepParent build/LidOn.app $ZIP
SHA=$(shasum -a 256 $ZIP | cut -d' ' -f1)
echo "$SHA  LidOn-$V.zip" > $ZIP.sha256

sed -e "s|__VERSION__|$V|" -e "s|__SHA256__|$SHA|" -e "s|__REPO__|$GITHUB_REPO|g" \
    packaging/lidon.rb.template > dist/lidon.rb

echo
echo "✓ $ZIP"
echo "  sha256 $SHA"
echo "✓ dist/lidon.rb  (homebrew tap 저장소의 Casks/ 에 복사하세요)"
echo
echo "다음 단계:"
echo "  git tag v$V && git push origin v$V      # GitHub Actions가 릴리스를 만들어요"
echo "  또는: gh release create v$V $ZIP $ZIP.sha256 --generate-notes"
