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
find . -name "LaunchScreen.storyboard" -exec rm {} \;

echo "Stap 1: App compileren (met omzeiling van Storyboard compilatie)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  IBC_ERRORS=NO \
  IBC_WARNINGS=NO \
  IBC_NOTICES=NO \
  archive

echo "Stap 2: Applicatiebestanden verzamelen..."
cp -R "$ARCHIVE/Products/Applications/" "$EXPORT/" 2>/dev/null || true

echo "Build voltooid! De bestanden staan in: $EXPORT"
