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

echo "Stap 2: iOS Project configuratie aanmaken..."
cat << 'EOF' > "$ROOT/project.yml"
name: VIDIYOW
options:
  bundleIdPrefix: com.sideload
targets:
  VIDIYOW:
    type: application
    platform: iOS
    deploymentTarget: "15.0"
    sources: [VIDIYOW]
    settings:
      CODE_SIGNING_ALLOWED: NO
      CODE_SIGNING_REQUIRED: NO
      CODE_SIGN_IDENTITY: ""
EOF

echo "Stap 3: Schoon Xcode project genereren..."
xcodegen generate

echo "Stap 4: Projectformaat handmatig downgraden naar Xcode 15 (objectVersion 60)..."
# Dit commando zoekt objectVersion = 77 (Xcode 16) op en vervangt het door 60 (Xcode 15)
sed -i '' 's/objectVersion = 77;/objectVersion = 60;/g' "$ROOT/VIDIYOW.xcodeproj/project.pbxproj" || true

echo "Stap 5: App compileren voor echte iPhone (iOS Device)..."
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
  build

echo "Build voltooid! De bestanden staan in: $EXPORT"
