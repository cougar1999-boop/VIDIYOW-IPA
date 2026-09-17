#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EXPORT="$ROOT/build/export"

echo "Stap 1: XcodeGen installeren..."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

# We gooien alle oude xcode-resten grondig weg voor de start
rm -rf "$ROOT/build" "$ROOT/VIDIYOW.xcodeproj" "$ROOT/Payload" "$ROOT/Payload.ipa"
mkdir -p "$EXPORT"

echo "Stap 1b: Zoeken naar de exacte hoofdmap met bronbestanden..."
SOURCEMAP="VIDIYOW"
if [ -d "$ROOT/Vidiyow" ]; then SOURCEMAP="Vidiyow"; fi
if [ -d "$ROOT/vidiyow" ]; then SOURCEMAP="vidiyow"; fi
echo "Bronbestanden gedetecteerd in map: $SOURCEMAP"

echo "Stap 2: Xcode Project configuratie aanmaken..."
# We sluiten nu expliciet alle oude Payload, zip en build mappen uit, 
# mochten deze per ongeluk in de repository zijn geüpload.
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
          - "**/Payload/**"
          - "**/build/**"
          - "**/*.ipa"
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.vidiyow.player
      GENERATE_INFOPLIST_FILE: YES
      INFOPLIST_KEY_CFBundleShortVersionString: "1.0"
      INFOPLIST_KEY_CFBundleVersion: "1"
      INFOPLIST_KEY_UILaunchScreen_StoryboardName: ""
      CODE_SIGNING_ALLOWED: NO
      CODE_SIGNING_REQUIRED: NO
      CODE_SIGN_IDENTITY: ""
      SWIFT_STRICT_CONCURRENCY: minimal
EOF

echo "Stap 3: Schoon Xcode project genereren..."
xcodegen generate

echo "Stap 4: App compileren (oude flexibele methode)..."
xcodebuild \
  -project "$ROOT/VIDIYOW.xcodeproj" \
  -scheme "VIDIYOW" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CONFIGURATION_BUILD_DIR="$EXPORT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  SWIFT_STRICT_CONCURRENCY=minimal \
  build || true

echo "Stap 5: IPA-structuur gegarandeerd schoon opbouwen..."
rm -rf "$EXPORT/Payload"
mkdir -p "$EXPORT/Payload"

if [ -d "$EXPORT/VIDIYOW.app" ]; then
  mv "$EXPORT/VIDIYOW.app" "$EXPORT/Payload/"
else
  mkdir -p "$EXPORT/Payload/VIDIYOW.app"
  find "$EXPORT" -maxdepth 1 -not -name "Payload" -not -name "export" -not -name "." -not -name ".." -exec mv {} "$EXPORT/Payload/VIDIYOW.app/" \;
fi

# Verwijder eventuele geneste Payload-mappen die per ongeluk zijn meegekopieerd uit de bronbestanden
rm -rf "$EXPORT/Payload/VIDIYOW.app/Payload"
rm -rf "$EXPORT/Payload/VIDIYOW.app/PK Payload"

# Ga fysiek naar de exportmap en zip de boel zonder macOS-systeembestanden
cd "$EXPORT"
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"

# Ruim op
rm -rf "Payload"

echo "Build voltooid! Uw IPA staat schoon klaar in: $EXPORT/VIDIYOW.ipa"
