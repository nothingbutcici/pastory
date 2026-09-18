#!/usr/bin/env bash
# Builds "Pastory.app". SIGN_ID=<Developer ID> keeps the screen-recording
# permission across rebuilds; the ad-hoc default resets it every time.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
# A Developer ID identity in the keychain is used automatically (same signature as the shipped app, so permissions
# carry over between a local build and a release); otherwise ad-hoc.
if [ -z "${SIGN_ID:-}" ]; then
    IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    DEV="$(echo "$IDS" | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
    if [ -n "$DEV" ]; then
        SIGN_ID="$DEV"
    else
        SIGN_ID="-"
    fi
fi

# ARCHS="arm64 x86_64" builds each slice (per-triple, works without full Xcode) and lipo's them; default is this machine only.
if [ -n "${ARCHS:-}" ]; then
    SLICES=()
    for a in $ARCHS; do
        # SwiftPM's per-triple build database goes stale after host builds ("command … not registered"): wipe and retry once.
        swift build -c "$CONFIG" --triple "$a-apple-macosx" || { rm -rf ".build/$a-apple-macosx"; swift build -c "$CONFIG" --triple "$a-apple-macosx"; }
        SLICES+=("$(swift build -c "$CONFIG" --triple "$a-apple-macosx" --show-bin-path)/Pastory")
    done
    mkdir -p build
    lipo -create "${SLICES[@]}" -output build/Pastory-universal
    BIN="build/Pastory-universal"
else
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Pastory"
fi

APP="build/Pastory.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pastory"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -d Resources/Fonts ] && cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
for f in AppIcon.icns Logo.png Pushpin.png MenuIcon.png MenuIcon@2x.png; do
    [ -f "Resources/$f" ] && cp "Resources/$f" "$APP/Contents/Resources/$f"
done

# A Developer ID identity gets the hardened runtime + secure timestamp that notarization requires.
SIGN_FLAGS=()
case "$SIGN_ID" in "Developer ID Application"*) SIGN_FLAGS=(--options runtime --timestamp);; esac
if ! codesign --force --sign "$SIGN_ID" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --entitlements Resources/Pastory.entitlements "$APP" 2>/dev/null; then
    codesign --force --sign "$SIGN_ID" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} "$APP"
fi
echo "→ $APP (signed: $SIGN_ID)"
