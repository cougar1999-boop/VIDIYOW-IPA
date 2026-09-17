#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EXPORT="$ROOT/build/export"
TEMP_BUILD="$ROOT/build/temp"

echo "Stap 1: XcodeGen installeren..."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

rm -rf "$ROOT/build" "$ROOT/VIDIYOW.xcodeproj"
mkdir -p "$EXPORT"
mkdir -p "$TEMP_BUILD"

echo "Stap 2: Swift programmeerfout in NativePlayerViewController automatisch repareren..."
# We vervangen de foutieve 'multiplier: 0.22' door een geldige 'constant: 22' om de UIKit crash te herstellen
FILE="$ROOT/VIDIYOW/Player/NativePlayerViewController.swift"
if [ -f "$FILE" ]; then
  sed -i '' 's/multiplier: 0.22/constant: 22/g' "$FILE" || true
fi

echo "Stap 3: iOS Project configuratie aanmaken..."
cat << 'EOF' > "$ROOT/project.yml"
name: VIDIYOW
options:
  bundleIdPrefix: com.vidiyow
targets:
  VIDIYOW:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: VIDIYOW
        excludes:
          - "**/*.storyboard"
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.vidiyow.player
      CODE_SIGNING_ALLOWED: NO
      CODE_SIGNING_REQUIRED: NO
      CODE_SIGN_IDENTITY: ""
      SWIFT_STRICT_CONCURRENCY: minimal
EOF

echo "Stap 4: Schoon Xcode project genereren..."
xcodegen generate

echo "Stap 5: App compileren voor echte iPhone..."
xcodebuild \
  -project "$ROOT/VIDIYOW.xcodeproj" \
  -scheme "VIDIYOW" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CONFIGURATION_BUILD_DIR="$TEMP_BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  SWIFT_STRICT_CONCURRENCY=minimal \
  build

echo "Stap 6: Geldige IPA-structuur aanmaken en inpakken..."
# Maak de verplichte Payload-map aan binnen de export-map
mkdir -p "$EXPORT/Payload"

# Kopieer de gecompileerde .app-bundel naar de Payload-map
cp -r "$TEMP_BUILD/VIDIYOW.app" "$EXPORT/Payload/"

# Ga naar de exportmap om de Payload-map te zippen naar een .ipa-bestand
cd "$EXPORT"
zip -r "VIDIYOW.ipa" "Payload"

# Ruim de tijdelijke mappen op zodat alleen het .ipa-bestand overblijft voor GitHub Artifacts
rm -rf "Payload"
rm -rf "$TEMP_BUILD"

echo "Build voltooid! Uw geldige IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
