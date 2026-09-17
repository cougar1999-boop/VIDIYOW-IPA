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

echo "Stap 5: App compileren voor echte iPhone..."
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
  build

echo "Build voltooid! De bestanden staan in: $EXPORT"
