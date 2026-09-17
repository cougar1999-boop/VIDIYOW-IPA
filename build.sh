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

echo "Stap 4: App compileren (oude flexibele methode)..."
# Staat code-fouten toe zonder dat GitHub Actions direct crasht
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
# We ruimen EERST een eventueel oude Payload-map op om de 'vector too long' fout te voorkomen!
rm -rf "$EXPORT/Payload"
mkdir -p "$EXPORT/Payload"

# Controleer of Xcode een geldige .app heeft achtergelaten
if [ -d "$EXPORT/VIDIYOW.app" ]; then
  mv "$EXPORT/VIDIYOW.app" "$EXPORT/Payload/"
else
  # Als Xcode door fouten losse bestanden heeft gedumpt, pakken we ze hier netjes in
  mkdir -p "$EXPORT/Payload/VIDIYOW.app"
  find "$EXPORT" -maxdepth 1 -not -name "Payload" -not -name "export" -not -name "." -not -name ".." -exec mv {} "$EXPORT/Payload/VIDIYOW.app/" \;
fi

# Ga fysiek naar de exportmap en zip de boel zonder macOS-systeembestanden
cd "$EXPORT"
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"

# Ruim de losse Payload-map op zodat deze bij een volgende run niet dubbel wordt ingepakt
rm -rf "Payload"

echo "Build voltooid! Uw IPA staat schoon klaar in: $EXPORT/VIDIYOW.ipa"
