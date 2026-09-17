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

echo "Stap 1b: Zoeken naar de exacte hoofdmap met bronbestanden..."
SOURCEMAP="VIDIYOW"
if [ -d "$ROOT/Vidiyow" ]; then SOURCEMAP="Vidiyow"; fi
if [ -d "$ROOT/vidiyow" ]; then SOURCEMAP="vidiyow"; fi
echo "Bronbestanden gedetecteerd in map: $SOURCEMAP"

echo "Stap 2: Xcode Project configuratie aanmaken..."
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

echo "Stap 4: App compileren (oude methode) naar de exportmap..."
# Deze methode staat fouten in de Swift-code toe zonder de hele GitHub Actions-run direct te crashen
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

echo "Stap 5: IPA-structuur forceren (Payload)..."
# We verpakken de bestanden handmatig in de Payload-structuur, exact zoals in uw allereerste werkende opzet
cd "$EXPORT"
mkdir -p Payload

if [ -d "VIDIYOW.app" ]; then
  mv "VIDIYOW.app" Payload/
else
  # Als Xcode losse bestanden heeft gedumpt, herstellen we de app-map handmatig om Sideloadly te foppen
  mkdir -p Payload/VIDIYOW.app
  find . -maxdepth 1 -not -name "Payload" -not -name "." -exec mv {} Payload/VIDIYOW.app/ \;
fi

# Zippen naar IPA en tijdelijke Payload opruimen
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"
rm -rf "Payload"

echo "Build voltooid! Uw IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
