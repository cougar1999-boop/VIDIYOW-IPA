#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EXPORT="$ROOT/build/export"

echo "Stap 1: XcodeGen installeren..."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

rm -rf "$ROOT/build" "$ROOT/VIDIYOW.xcodeproj"
mkdir -p "$EXPORT"

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

echo "Stap 5: App archiveren voor echte iPhone..."
# We maken een officieel Xcode archief aan om de executable te garanderen
xcodebuild \
  -project "$ROOT/VIDIYOW.xcodeproj" \
  -scheme "VIDIYOW" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/build/VIDIYOW.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  SWIFT_STRICT_CONCURRENCY=minimal \
  archive

echo "Stap 6: Geldige IPA-structuur handmatig samenstellen..."
# Zorg dat de exportmap en Payload-map volledig schoon zijn
rm -rf "$EXPORT"
mkdir -p "$EXPORT/Payload"

# Kopieer de ALTIJD complete .app vanuit het gemaakte archief naar de Payload-map
cp -r "$ROOT/build/VIDIYOW.xcarchive/Products/Applications/VIDIYOW.app" "$EXPORT/Payload/"

# Ga fysiek naar de exportmap om foutieve paden in de zip te voorkomen
cd "$EXPORT"

# We zippen en sluiten onzichtbare macOS-bestanden (zoals UT en .DS_Store) expliciet uit
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"

# Ruim de losse Payload-map en het xcarchive-pakket netjes op
rm -rf "Payload"
rm -rf "$ROOT/build/VIDIYOW.xcarchive"

echo "Build voltooid! Uw geldige IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
