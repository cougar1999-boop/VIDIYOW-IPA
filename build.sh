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

echo "Stap 1b: Zoeken naar de juiste hoofdmap met bronbestanden..."
# We zoeken automatisch of de map VIDIYOW, Vidiyow of vidiyow heet
SOURCEMAP="VIDIYOW"
if [ -d "$ROOT/Vidiyow" ]; then SOURCEMAP="Vidiyow"; fi
if [ -d "$ROOT/vidiyow" ]; then SOURCEMAP="vidiyow"; fi
echo "Bronbestanden gevonden in map: $SOURCEMAP"

echo "Stap 2: Swift programmeerfout in NativePlayerViewController automatisch repareren..."
FILE="$ROOT/$SOURCEMAP/Player/NativePlayerViewController.swift"
if [ -f "$FILE" ]; then
  sed -i '' 's/multiplier: 0.22/constant: 22/g' "$FILE" || true
else
  # Als de mapstructuur anders is, herstel het bestand overal waar het staat
  find "$ROOT" -name "NativePlayerViewController.swift" -exec sed -i '' 's/multiplier: 0.22/constant: 22/g' {} + || true
fi

echo "Stap 3: iOS Project configuratie aanmaken..."
cat << EOF > "$ROOT/project.yml"
name: VIDIYOW
options:
  bundleIdPrefix: com.vidiyow
targets:
  VIDIYOW:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: $SOURCEMAP
        excludes:
          - "**/*.storyboard"
          - "**/Info.plist"
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
rm -rf "$EXPORT"
mkdir -p "$EXPORT/Payload"

# Kopieer de .app vanuit het gemaakte archief naar de Payload-map
cp -r "$ROOT/build/VIDIYOW.xcarchive/Products/Applications/VIDIYOW.app" "$EXPORT/Payload/"

echo "Stap 6b: Controleren of de executable (de app-motor) daadwerkelijk bestaat..."
if [ ! -f "$EXPORT/Payload/VIDIYOW.app/VIDIYOW" ]; then
  echo "CRITIEKE FOUT: Het uitvoerbare bestand 'VIDIYOW' is niet gegenereerd in de .app map!"
  echo "Controleer de Xcode build logs hierboven om te zien waarom er geen code is gecompileerd."
  exit 1
fi

# Ga fysiek naar de exportmap om foutieve paden in de zip te voorkomen
cd "$EXPORT"

# Zippen zonder macOS-systeembestanden
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"

# Ruim de tijdelijke mappen netjes op
rm -rf "Payload"
rm -rf "$ROOT/build/VIDIYOW.xcarchive"

echo "Build voltooid! Uw geldige IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
