#!/usr/bin/env bash
# Runs the unit tests. With full Xcode installed, plain `swift test` works; the
# Command Line Tools ship Swift Testing outside the default search paths, so
# point the compiler and the loader at it when that is what's selected.
set -euo pipefail
cd "$(dirname "$0")/.."

dev="$(xcode-select -p)"
if [[ "$dev" == *CommandLineTools* ]]; then
  fw="$dev/Library/Developer/Frameworks"
  lib="$dev/Library/Developer/usr/lib"
  exec swift test -Xswiftc -F"$fw" -Xlinker -F"$fw" \
    -Xlinker -rpath -Xlinker "$fw" -Xlinker -rpath -Xlinker "$lib" "$@"
fi
exec swift test "$@"
