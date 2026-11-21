#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-PadWake}"
BUNDLE_ID="${BUNDLE_ID:-com.padwake.app}"
VERSION="${VERSION:-1.4.1}"
UNIVERSAL="${UNIVERSAL:-0}"
MIN_MACOS="${MIN_MACOS:-13.0}"

BUILD_DIR="$REPO_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
OBJ_DIR="$BUILD_DIR/obj"
MOD_CACHE="$BUILD_DIR/module-cache"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$OBJ_DIR" "$MOD_CACHE"

compile_arch() {
    local arch="$1"
    local target="${arch}-apple-macos${MIN_MACOS}"
    local core_obj="$OBJ_DIR/padwake_core_${arch}.o"
    local out_bin="$OBJ_DIR/${APP_NAME}_${arch}"

    echo "[build] Compiling C core (${arch})..."
    clang -arch "$arch" -mmacosx-version-min="$MIN_MACOS" \
        -Wall -Wextra -Wformat -Wformat-security \
        -Werror=implicit-function-declaration -Werror=return-type \
        -O2 -std=c11 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fno-common \
        -c "$REPO_DIR/src/padwake_core.c" -o "$core_obj"

    echo "[build] Compiling Swift app (${arch})..."
    swiftc -module-cache-path "$MOD_CACHE" \
        -target "$target" -O -parse-as-library \
        -import-objc-header "$REPO_DIR/src/padwake_core.h" \
        "$REPO_DIR/app/PadWakeApp.swift" "$core_obj" \
        -framework Cocoa -framework SwiftUI -framework ServiceManagement \
        -framework IOKit -framework CoreFoundation \
        -o "$out_bin"
}

if [[ "$UNIVERSAL" == "1" ]]; then
    compile_arch arm64
    compile_arch x86_64
    lipo -create "$OBJ_DIR/${APP_NAME}_arm64" "$OBJ_DIR/${APP_NAME}_x86_64" -output "$MACOS_DIR/$APP_NAME"
    echo "[build] Created universal binary (arm64 + x86_64)"
else
    HOST_ARCH="$(uname -m)"
    compile_arch "$HOST_ARCH"
    cp "$OBJ_DIR/${APP_NAME}_${HOST_ARCH}" "$MACOS_DIR/$APP_NAME"
fi

# Bundle Info.plist safely via PlistBuddy (no fragile sed substitution)
cp "$REPO_DIR/app/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Build & copy AppIcon.icns
if [[ -f "$REPO_DIR/assets/logo.png" ]]; then
    "$REPO_DIR/scripts/make-icns.sh" "$REPO_DIR/assets/logo.png" "$RES_DIR/AppIcon.icns"
fi

# Bundle game mapping templates under Resources/games/ (supports multiple games)
rm -rf "$RES_DIR/games" "$RES_DIR/gamecontrollerdb_padwake.txt" "$RES_DIR/GamePadConfig_PadWake.json"
cp -R "$REPO_DIR/games" "$RES_DIR/games"

# Ad-hoc sign by default so the app runs cleanly locally without a Developer ID cert
if [[ "${SKIP_ADHOC_SIGN:-0}" != "1" ]]; then
    codesign --force --sign - --entitlements "$REPO_DIR/app/PadWake.entitlements" "$APP_BUNDLE"
    echo "[build] Ad-hoc signed $APP_BUNDLE"
fi

echo "[build] Ready: $APP_BUNDLE"
