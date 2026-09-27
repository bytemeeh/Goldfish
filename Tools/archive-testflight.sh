#!/bin/bash
# Produce a signed archive after Apple membership activation. Does not upload.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GOLDFISH_TEAM_ID:?Set GOLDFISH_TEAM_ID to the activated Apple Developer team ID.}"
archive_path="${GOLDFISH_ARCHIVE_PATH:-$PWD/build/Goldfish.xcarchive}"
email=$(/usr/libexec/PlistBuddy -c 'Print :FeedbackSupportEmail' Goldfish/Info.plist)
if [[ -z "$email" ]]; then
  echo "Configure the confirmed FeedbackSupportEmail before archiving for testers." >&2
  exit 1
fi
xcodebuild -project Goldfish.xcodeproj -scheme Goldfish -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$GOLDFISH_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates archive
printf 'Archive created: %s\nOpen it in Xcode Organizer, validate, then Distribute App → TestFlight & App Store.\n' "$archive_path"
