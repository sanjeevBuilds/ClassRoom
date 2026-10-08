#!/usr/bin/env bash
# Download script for native iOS framework dependencies (OpenCV + ONNX Runtime).
# Unpacks prebuilt opencv2.framework into native/third_party/ and prepares iOS CocoaPods.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/native/third_party"

mkdir -p "$THIRD_PARTY_DIR"

OPENCV_ZIP="$THIRD_PARTY_DIR/opencv-4.14.0-ios-framework.zip"
OPENCV_FRAMEWORK="$THIRD_PARTY_DIR/opencv2.framework"

if [ -d "$OPENCV_FRAMEWORK" ]; then
    echo "✓ OpenCV iOS framework already present at $OPENCV_FRAMEWORK"
else
    echo "Downloading OpenCV 4.14.0 iOS framework..."
    curl -L "https://github.com/opencv/opencv/releases/download/4.14.0/opencv-4.14.0-ios-framework.zip" -o "$OPENCV_ZIP"
    echo "Unzipping opencv2.framework into $THIRD_PARTY_DIR..."
    unzip -q "$OPENCV_ZIP" -d "$THIRD_PARTY_DIR"
    rm -f "$OPENCV_ZIP"
    echo "✓ OpenCV iOS framework installed."
fi

echo "Running CocoaPods setup for iOS project..."
if command -v pod >/dev/null 2>&1; then
    cd "$ROOT_DIR/ios"
    pod install
    echo "✓ CocoaPods dependencies installed successfully."
else
    echo "Notice: CocoaPods ('pod') CLI tool not found. Install CocoaPods ('gem install cocoapods') to run 'pod install' on macOS."
fi
