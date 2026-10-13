#!/usr/bin/env bash
# Builds Lineup and a small fixture app, then runs the end-to-end test: real
# windows, real global shortcuts, real Accessibility calls. Only the fixture's
# windows are tiled during the run; nothing else on screen is touched.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
bin="$(swift build --show-bin-path)"

fixture="$bin/LineupFixture.app"
mkdir -p "$fixture/Contents/MacOS"
cp Tests/e2e/Fixture-Info.plist "$fixture/Contents/Info.plist"
swiftc -O -target "$(uname -m)-apple-macos13.0" Tests/e2e/Fixture.swift -o "$fixture/Contents/MacOS/LineupFixture"
xattr -cr "$fixture"
codesign --force --sign - "$fixture"

exec swift Tests/e2e/e2e.swift "$bin/Lineup" "$fixture"
