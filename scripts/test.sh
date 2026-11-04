#!/usr/bin/env bash
# swift test that also works with only the Command Line Tools (no Xcode),
# where SwiftPM doesn't find the Swift Testing macro plugin on its own.
set -euo pipefail
cd "$(dirname "$0")/.."
args=()
if [[ $(xcode-select -p) == */CommandLineTools ]]; then
  args=(-Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing")
fi
exec swift test ${args[@]+"${args[@]}"} "$@"
