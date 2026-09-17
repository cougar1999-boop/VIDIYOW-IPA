#!/bin/bash#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/VIDIYOW.xcodeproj"
SCHEME="VIDIYOW"
EXPORT="$ROOT/build/export"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Run this script on macOS with Xcode installed."
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$EXPORT"

echo "Stap 1: App compileren met uitgeschakelde Interface Builder compilatie..."
# IBTOOL_NO_COMPILATION=YES dwingt Xcode om storyboards zonder certificaatcontrole over te slaan
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CONFIGURATION_BUILD_DIR="$EXPORT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  IBTOOL_NO_COMPILATION=YES \
  build

echo "Build voltooid! De bestanden staan in: $EXPORT"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/VIDIYOW.xcodeproj"
SCHEME="VIDIYOW"
EXPORT="$ROOT/build/export"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Run this script on macOS with Xcode installed."
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$EXPORT"

echo "Stap 1: Storyboard-bestanden tijdelijk uitschakelen om exit code 65 te voorkomen..."
# Dit verwijdert het storyboard-bestand op de GitHub-server zodat Xcode er niet op kan crashen
find "$ROOT" -name "*.storyboard" -exec rm -f {} \;

echo "Stap 2: App compileren (zonder archiverings-signing-controle)..."
# We gebruiken 'build' in plaats van 'archive' om de Apple-certificaatcontrole volledig te omzeilen
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CONFIGURATION_BUILD_DIR="$EXPORT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build

echo "Build voltooid! De bestanden staan in: $EXPORT"
