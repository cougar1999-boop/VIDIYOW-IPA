#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/VIDIYOW.xcodeproj"
SCHEME="VIDIYOW"
ARCHIVE="$ROOT/build/VIDIYOW.xcarchive"
EXPORT="$ROOT/build/export"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Run this script on macOS with Xcode installed."
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$EXPORT"

# Archive stap: we dwingen Xcode om signing over te slaan
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

# ExportOptions.plist: aangepast voor ad-hoc/development zonder certificaten
cat > "$ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>signingStyle</key><string>manual</string>
  <key>compileBitcode</key><false/>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST

# Export stap: we exporteren de ongetekende app
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/build/ExportOptions.plist" \
  -exportPath "$EXPORT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

echo
echo "Build voltooid! De bestanden staan in: $EXPORT"
