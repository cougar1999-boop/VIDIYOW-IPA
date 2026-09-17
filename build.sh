#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EXPORT="$ROOT/build/export"

# Installeer XcodeGen op de GitHub Mac-server via Homebrew
echo "Stap 1: XcodeGen installeren..."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

rm -rf "$ROOT/build" "$ROOT/VIDIYOW.xcodeproj"
mkdir -p "$EXPORT"

echo "Stap 2: iOS Project configuratie aanmaken..."
# We schrijven een configuratiebestand dat een puur iOS (iPhone/iPad) project afdwingt
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

echo "Stap 4: App compileren voor echte iPhone (iOS Device)..."
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
