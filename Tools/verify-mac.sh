#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This check requires macOS and Xcode. No build was attempted." >&2
  exit 1
fi
xcodebuild -version
if command -v xcodegen >/dev/null; then
  xcodegen generate --spec project.yml
else
  echo "XcodeGen is optional; using the synchronized checked-in Goldfish.xcodeproj."
fi
mkdir -p Verification
xcodebuild -project Goldfish.xcodeproj -scheme Goldfish -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build | tee Verification/build.log
if [[ -n "${GOLDFISH_SIMULATOR_ID:-}" ]]; then
  xcodebuild -project Goldfish.xcodeproj -scheme Goldfish -destination "platform=iOS Simulator,id=$GOLDFISH_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO test | tee Verification/tests.log
else
  echo "Build command finished. Tests were NOT run. Set GOLDFISH_SIMULATOR_ID to an installed simulator UUID and rerun."
  xcrun simctl list devices available
fi
