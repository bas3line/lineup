#!/usr/bin/env bash
# Builds a release Lineup.app for this Mac's architecture into dist/, ad-hoc
# signed, plus dist/Lineup.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)"

# Sign in a scratch directory: folders synced by iCloud or Finder can carry
# extended attributes that codesign rejects.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Lineup.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Lineup" "$app/Contents/MacOS/Lineup"
cp Resources/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

mkdir -p dist
rm -rf dist/Lineup.app dist/Lineup.zip
ditto -c -k --keepParent "$app" dist/Lineup.zip
ditto --noextattr --norsrc "$app" dist/Lineup.app
echo "Built dist/Lineup.app and dist/Lineup.zip"
