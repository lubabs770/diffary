#!/usr/bin/env bash
# Install the CI-built GhosttyKit for the pinned Ghostty commit into Frameworks/.
set -euo pipefail
cd "$(dirname "$0")/.."
sha=$(tr -d '[:space:]' < GHOSTTY_COMMIT)
stamp=Frameworks/.ghosttykit-commit
if [[ -f $stamp && $(cat "$stamp") == "$sha" ]]; then exit 0; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh release download "ghosttykit-$sha" -p GhosttyKit.xcframework.zip -D "$tmp"
rm -rf Frameworks/GhosttyKit.xcframework
mkdir -p Frameworks
unzip -q "$tmp/GhosttyKit.xcframework.zip" -d Frameworks
echo "$sha" > "$stamp"
echo "GhosttyKit $sha installed"
