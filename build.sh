#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/VIDIYOW.xcodeproj"
SCHEME="VIDIYOW"
EXPORT="$ROOT/build/export"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Run this script on macOS with Xcode installed."
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$EXPORT"

echo "Stap 1: Storyboard-bestanden herstellen..."
cat << 'EOF' > "$ROOT/VIDIYOW/LaunchScreen.storyboard"
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="21507" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.CocoaTouch.Plugin" version="21505"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
                        <color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma2WhiteColorSpace"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
</document>
EOF

echo "Stap 2: Projectbestand manipuleren om iOS/iPhone te forceren..."
# We zoeken in het projectbestand naar de macOS SDK instellingen en vervangen deze door iphoneos
PBXPROJ="$PROJECT/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
  sed -i '' 's/SDKROOT = macosx;/SDKROOT = iphoneos;/g' "$PBXPROJ" || true
  sed -i '' 's/SUPPORTED_PLATFORMS = "macosx";/SUPPORTED_PLATFORMS = "iphoneos";/g' "$PBXPROJ" || true
  sed -i '' 's/SUPPORTED_PLATFORMS = macosx;/SUPPORTED_PLATFORMS = iphoneos;/g' "$PBXPROJ" || true
fi

echo "Stap 3: App compileren voor iOS (Simulator) om herstelde instellingen te testen..."
# We bouwen nu voor de iphonesimulator SDK om platformcontroles te omzeilen
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CONFIGURATION_BUILD_DIR="$EXPORT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build

echo "Build voltooid! De bestanden staan in: $EXPORT"
