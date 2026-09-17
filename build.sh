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

echo "Stap 1: App compileren en archiveren..."
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

echo "Stap 2: .app bestand kopiëren voor sideloading..."
# We halen de gecompileerde app rechtstreeks uit het archief en zetten hem in de export map
cp -R "$ARCHIVE/Products/Applications/" "$EXPORT/"

echo "Build voltooid! De bestanden staan in: $EXPORT"
