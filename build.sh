#!/bin/bash
# build.sh — Compile DDMStatusApp and package it as a .app bundle
#
# Usage:
#   ./build.sh              Build for the current architecture
#   ./build.sh universal    Build a universal binary (arm64 + x86_64)

set -euo pipefail

APP_NAME="DDMStatusApp"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
MIN_TARGET="13.0"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"

if [ "${1:-}" = "universal" ]; then
    echo "==> Building universal binary (arm64 + x86_64)..."
    swiftc -o "${BUILD_DIR}/${APP_NAME}-arm64" "${APP_NAME}.swift" \
        -framework Cocoa -framework SwiftUI \
        -target arm64-apple-macos${MIN_TARGET} \
        -parse-as-library -O

    swiftc -o "${BUILD_DIR}/${APP_NAME}-x86_64" "${APP_NAME}.swift" \
        -framework Cocoa -framework SwiftUI \
        -target x86_64-apple-macos${MIN_TARGET} \
        -parse-as-library -O

    lipo -create \
        "${BUILD_DIR}/${APP_NAME}-arm64" \
        "${BUILD_DIR}/${APP_NAME}-x86_64" \
        -output "${MACOS_DIR}/${APP_NAME}"

    rm "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
else
    ARCH=$(uname -m)
    echo "==> Building for ${ARCH}..."
    swiftc -o "${MACOS_DIR}/${APP_NAME}" "${APP_NAME}.swift" \
        -framework Cocoa -framework SwiftUI \
        -target "${ARCH}-apple-macos${MIN_TARGET}" \
        -parse-as-library -O
fi

echo "==> Creating app bundle..."
cp Info.plist "${APP_BUNDLE}/Contents/"

echo "==> Done! App bundle created at: ${APP_BUNDLE}"
echo "    To install: cp -R ${APP_BUNDLE} /Applications/"
