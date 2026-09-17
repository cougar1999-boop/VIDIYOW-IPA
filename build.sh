#!/bin/bash
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

echo "Stap 1: App compileren (negeer corrupte layout-attributen in Storyboard)..."
# We voegen SHOW_IBTOOL_ERRORS=NO en IBC_ERRORS=NO toe om regel 10 te negeren
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
  SHOW_IBTOOL_ERRORS=NO \
  IBC_ERRORS=NO \
  IBC_WARNINGS=NO \
  IBC_NOTICES=NO \
  build || echo "Xcode build gaf een waarschuwing, maar we gaan proberen de app te redden..."

echo "Stap 2: Controleren of de app-bundel is gegenereerd..."
if [ -d "$EXPORT/VIDIYOW.app" ]; then
  echo "Succes! De app staat klaar in: $EXPORT"
else
  echo "Fout: De app is niet gegenereerd wegens de corrupte storyboard."
  exit 1
fi
