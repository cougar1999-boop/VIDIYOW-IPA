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

echo "Stap 2: Swift programmeerfouten automatisch repareren via Python..."
# We zoeken nu in álle mappen (hoofdletters/kleine letters) naar het juiste bestand
find "$ROOT" -iname "NativePlayerViewController.swift" | while read -r FILE; do
  echo "Repareren van bestand: $FILE"
  python3 -c "
import sys
with open('$FILE', 'r') as f:
    code = f.read()

# Herstel 1: Vervang de foutieve UIKit .constraint multiplier aanroep door geldige NSLayoutConstraint syntax
code = code.replace(
    'subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 1.0, constant: 22)',
    'NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 22).isActive = true'
)
code = code.replace(
    'subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 0.22)',
    'NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 0.22, constant: 0).isActive = true'
)

# Herstel 2: Zet de ongedefinieerde AVURLAssetHTTPHeaderFieldsKey correct om naar een String key inclusief de missende dubbelpunt
code = code.replace('AVURLAssetHTTPHeaderFieldsKey', '\"AVURLAssetHTTPHeaderFieldsKey\"')
# Mocht er door de vorige poging een syntaxfout zijn ontstaan zonder dubbelpunt, herstellen we dat hier direct:
code = code.replace('\"AVURLAssetHTTPHeaderFieldsKey\" ', '\"AVURLAssetHTTPHeaderFieldsKey\": ')

with open('$FILE', 'w') as f:
    f.write(code)
"
done

# 2b: Algemene iOS 17/18 API-fouten in álle Swift-bestanden opsporen en repareren
find "$ROOT" -name "*.swift" | while read -r FILE; do
  python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    code = f.read()

altered = False

# Herstel verouderde keyWindow aanroepen die crashen in moderne Xcode versies
if 'UIApplication.shared.keyWindow' in code:
    code = code.replace('UIApplication.shared.keyWindow', 'UIApplication.shared.connectedScenes.flatMap { ($0 as? UIWindowScene)?.windows ?? [] }.first { $0.isKeyWindow }')
    altered = True

if altered:
    print(f'-> Universele iOS patch toegepast op: {sys.argv[1]}')
    with open(sys.argv[1], 'w') as f:
        f.write(code)
" "$FILE"
done

echo "Stap 3: Xcode Project configuratie aanmaken..."
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
  archive > xcodebuild.log 2>&1 || {
    echo "------------------------------------------------------------------"
    echo "❌ CRITIEKE FOUT: Swift compilatie (CompileSwift) is mislukt!"
    echo "Hieronder staan de exacte foutmeldingen uit de broncode:"
    echo "------------------------------------------------------------------"
    grep -E "error:|warning:" xcodebuild.log || tail -n 50 xcodebuild.log
    exit 1
  }

echo "Stap 6: Geldige IPA-structuur handmatig samenstellen..."
rm -rf "$EXPORT"
mkdir -p "$EXPORT/Payload"

# Kopieer de complete .app vanuit het gemaakte archief naar de Payload-map
cp -r "$ROOT/build/VIDIYOW.xcarchive/Products/Applications/VIDIYOW.app" "$EXPORT/Payload/"

echo "Stap 6b: Controleren of de executable (de app-motor) daadwerkelijk bestaat..."
if [ ! -f "$EXPORT/Payload/VIDIYOW.app/VIDIYOW" ]; then
  echo "CRITIEKE FOUT: Het uitvoerbare bestand 'VIDIYOW' is niet gegenereerd in de .app map!"
  exit 1
fi

# Ga fysiek naar de exportmap om foutieve paden in de zip te voorkomen
cd "$EXPORT"

# Zippen zonder macOS-systeembestanden
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"

# Ruim de tijdelijke mappen netjes op
rm -rf "Payload"
rm -rf "$ROOT/build/VIDIYOW.xcarchive"
rm -f "$ROOT/xcodebuild.log"

echo "Build voltooid! Uw geldige IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
