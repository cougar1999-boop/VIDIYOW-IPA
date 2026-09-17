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
SOURCEMAP="VIDIYOW"
if [ -d "$ROOT/Vidiyow" ]; then SOURCEMAP="Vidiyow"; fi
if [ -d "$ROOT/vidiyow" ]; then SOURCEMAP="vidiyow"; fi
echo "Bronbestanden gevonden in map: $SOURCEMAP"

echo "Stap 2: Swift programmeerfouten in NativePlayerViewController automatisch repareren..."
FILE="$ROOT/$SOURCEMAP/Player/NativePlayerViewController.swift"

# Herstel 1: De foute Autolayout Constraint fixen met geldige NSLayoutConstraint syntaxis
if [ -f "$FILE" ]; then
  sed -i '' 's/subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 1.0, constant: 22)/NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 22)/g' "$FILE" || true
  sed -i '' 's/subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 0.22)/NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 0.22, constant: 0)/g' "$FILE" || true
else
  find "$ROOT" -name "NativePlayerViewController.swift" -exec sed -i '' 's/subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 1.0, constant: 22)/NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 22)/g' {} + || true
  find "$ROOT" -name "NativePlayerViewController.swift" -exec sed -i '' 's/subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 0.22)/NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 0.22, constant: 0)/g' {} + || true
fi

# Herstel 2: De ontbrekende AVURLAssetHTTPHeaderFieldsKey repareren naar een String key
if [ -f "$FILE" ]; then
  sed -i '' 's/AVURLAssetHTTPHeaderFieldsKey/"AVURLAssetHTTPHeaderFieldsKey"/g' "$FILE" || true
else
  find "$ROOT" -name "NativePlayerViewController.swift" -exec sed -i '' 's/AVURLAssetHTTPHeaderFieldsKey/"AVURLAssetHTTPHeaderFieldsKey"/g' {} + || true
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
      GENERATE_INFOPLIST_FILE: YES
      INFOPLIST_KEY_CFBundleShortVersionString: "1.0"
      INFOPLIST_KEY_CFBundleVersion: "1"
      INFOPLIST_KEY_UILaunchScreen_StoryboardName: ""
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
