#!/bin/zsh
# GitHub 계정/저장소 이름을 모든 파일에 반영: scripts/set-repo.sh myname/LidOn
set -euo pipefail
cd "$(dirname "$0")/.."
NEW=${1:?usage: scripts/set-repo.sh <owner/name>}
[[ "$NEW" == */* ]] || { echo "형식: owner/name" >&2; exit 1; }
OLD=$(sed -n 's/^GITHUB_REPO="\(.*\)"/\1/p' scripts/config.sh)
OLD_OWNER=${OLD%%/*}
NEW_OWNER=${NEW%%/*}
for f in scripts/config.sh install.sh README.md README.en.md plugin/.claude-plugin/plugin.json plugin/.mcp.json; do
  sed -i '' -e "s|$OLD|$NEW|g" -e "s|$OLD_OWNER/tap|$NEW_OWNER/tap|g" "$f"
done
echo "✓ $OLD → $NEW  (Homebrew tap: $NEW_OWNER/tap)"
