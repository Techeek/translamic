#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_ROOT="$ROOT_DIR/.build/pkg"
APP_DERIVED_DATA="$BUILD_ROOT/app"
DRIVER_DERIVED_DATA="$BUILD_ROOT/driver"
PAYLOAD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/translamic-payload.XXXXXX")"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_PATH="$DIST_DIR/translamic-${VERSION}.pkg"

cleanup() {
  rm -rf "$PAYLOAD_ROOT"
}

trap cleanup EXIT

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    printf 'error: version must use x.y.z format\n' >&2
    exit 1
    ;;
esac

mkdir -p "$DIST_DIR"

/bin/bash "$ROOT_DIR/scripts/prepare-moss-runtime.sh"

xcodebuild \
  -project "$ROOT_DIR/TranslaMic.xcodeproj" \
  -scheme TranslaMic \
  -configuration Release \
  -derivedDataPath "$APP_DERIVED_DATA" \
  -jobs 2 \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  MARKETING_VERSION="$VERSION" \
  build

xcodebuild \
  -project "$ROOT_DIR/Drivers/TranslaMicVirtualAudio/TranslaMicVirtualAudio.xcodeproj" \
  -scheme TranslaMicVirtualAudio \
  -configuration Release \
  -derivedDataPath "$DRIVER_DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  build

/usr/bin/ditto \
  "$APP_DERIVED_DATA/Build/Products/Release/TranslaMic.app" \
  "$PAYLOAD_ROOT/Applications/TranslaMic.app"

/usr/bin/ditto \
  "$DRIVER_DERIVED_DATA/Build/Products/Release/TranslaMicVirtualAudio.driver" \
  "$PAYLOAD_ROOT/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver"

# Ad-hoc signatures do not require an Apple Developer account, but give macOS
# internally consistent code objects for the app, framework, and HAL plug-in.
/usr/bin/codesign --force --deep --sign - "$PAYLOAD_ROOT/Applications/TranslaMic.app"
/usr/bin/codesign --force --sign - "$PAYLOAD_ROOT/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver"

/usr/bin/pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --identifier io.github.Techeek.TranslaMic.pkg \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$PACKAGE_PATH"

printf 'Created %s\n' "$PACKAGE_PATH"
printf 'This package is intentionally unsigned. Restart macOS after installation so Core Audio loads the driver.\n'
