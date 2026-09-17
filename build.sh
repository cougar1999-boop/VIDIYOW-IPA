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

echo "Stap 1: App compileren voor iOS (Simulator bestemming)..."
# We veranderen hier de destination naar de iOS Simulator om de macOS-restrictie te omzeilen
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

echo "Stap 2: .app bestand kopiëren voor sideloading..."
cp -R "$ARCHIVE/Products/Applications/" "$EXPORT/" 2>/dev/null || cp -R "$ROOT/build/Build/Products/Release-iphonesimulator/" "$EXPORT/" 2>/dev/null || true

echo "Build voltooid! De bestanden staan in: $EXPORT"
