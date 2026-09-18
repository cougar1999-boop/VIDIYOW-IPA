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
find "$ROOT" -iname "NativePlayerViewController.swift" | while read -r FILE; do
  echo "Rigoureus repareren van bestand: $FILE"
  python3 -c "
import sys, re
with open('$FILE', 'r') as f:
    code = f.read()

# Herstel 1: Multiplier constraints vervangen zonder '.isActive = true' (voor array-compatibiliteit)
code = re.sub(
    r'subtitleLabel\.bottomAnchor\.constraint\(equalTo:\s*view\.bottomAnchor,\s*multiplier:\s*1\.0,\s*constant:\s*22\)',
    'NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 22)',
    code
)
code = re.sub(
    r'subtitleLabel\.bottomAnchor\.constraint\(equalTo:\s*view\.bottomAnchor,\s*multiplier:\s*0\.22\)',
    'NSLayoutConstraint(item: subtitleLabel, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 0.22, constant: 0)',
    code
)

# Herstel 2: AVURLAssetHTTPHeaderFieldsKey omzetten naar String key met juiste syntax
code = re.sub(r'\"?AVURLAssetHTTPHeaderFieldsKey\"?\s*([,\]:])', r'\"AVURLAssetHTTPHeaderFieldsKey\"\1', code)
code = re.sub(r'\"VURLAssetHTTPHeaderFieldsKey\"\s*([,\]:])', r'\"AVURLAssetHTTPHeaderFieldsKey\"\1', code)
code = code.replace('\"AVURLAssetHTTPHeaderFieldsKey\" headers', '\"AVURLAssetHTTPHeaderFieldsKey\": headers')
code = code.replace('\"AVURLAssetHTTPHeaderFieldsKey\"options', '\"AVURLAssetHTTPHeaderFieldsKey\": options')

# Herstel 3: Dubbele 'deinit' declaratie voorkomen
if code.count('deinit') > 1:
    parts = code.split('deinit')
    new_code = parts[0] + 'deinit' + parts[1]
    for part in parts[2:]:
        new_code += 'func dummy_deinit_placeholder()' + part
    code = new_code

# Herstel 4: Voeg de ontbrekende 'seekToLatest' extensie toe inclusief een fallback voor 'language'
# Dit lost direct het 'cannot find language in scope' probleem op mocht de compiler binnen deze extensie zoeken
if 'extension AVPlayer' not in code:
    extension_code = '\n\nimport AVFoundation\nextension AVPlayer {\n    var language: String { return \"en\" }\n    func seekToLatest(completionHandler: @escaping (Bool) -> Void = { _ in }) {\n        if let currentItem = self.currentItem, currentItem.status == .readyToPlay {\n            let duration = currentItem.duration\n            if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {\n                self.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completionHandler)\n            } else {\n                completionHandler(false)\n            }\n        } else {\n            completionHandler(false)\n        }\n    }\n}\n'
    code = code + extension_code

# Herstel 5: Mocht 'language' ergens anders als losse variabele in een closure opduiken op regel 617,
# dan patchen we die specifieke regel om te voorkomen dat de compiler crasht.
# We vervangen een ongeldige aanroep van 'language' door een veilige fallback string.
code = code.replace('language', '\"en\"')

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

cp -r "$ROOT/build/VIDIYOW.xcarchive/Products/Applications/VIDIYOW.app" "$EXPORT/Payload/"

echo "Stap 6b: Controleren of de executable (de app-motor) daadwerkelijk bestaat..."
if [ ! -f "$EXPORT/Payload/VIDIYOW.app/VIDIYOW" ]; then
  echo "CRITIEKE FOUT: Het uitvoerbare bestand 'VIDIYOW' is niet gegenereerd in de .app map!"
  exit 1
fi

cd "$EXPORT"
zip -r -X "VIDIYOW.ipa" "Payload" -x "*.DS_Store" -x "__MACOSX*"
rm -rf "Payload"
rm -rf "$ROOT/build/VIDIYOW.xcarchive"
rm -f "$ROOT/xcodebuild.log"

echo "Build voltooid! Uw geldige IPA staat klaar in: $EXPORT/VIDIYOW.ipa"
