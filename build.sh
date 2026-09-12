#!/usr/bin/env bash
# Builds "Pastory.app". SIGN_ID=<Developer ID> keeps the screen-recording
# permission across rebuilds; the ad-hoc default resets it every time.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
# Prefer the local self-signed identity (tools/make-signing-cert.sh); ad-hoc otherwise.
if [ -z "${SIGN_ID:-}" ]; then
    IDS="$(security find-identity -v -p codesigning 2>/dev/null)"
    if echo "$IDS" | grep -q '"Snip Clip Dev"'; then
        SIGN_ID="Snip Clip Dev"
    elif echo "$IDS" | grep -q '"CC Record Dev"'; then
        SIGN_ID="CC Record Dev"      # same machine, same purpose: reuse instead of a second cert
    else
        SIGN_ID="-"
    fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SnipClip"

APP="build/Pastory.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pastory"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -d Resources/Fonts ] && cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
for f in AppIcon.icns Logo.png Pushpin.png MenuIcon.png MenuIcon@2x.png; do
    [ -f "Resources/$f" ] && cp "Resources/$f" "$APP/Contents/Resources/$f"
done

if ! codesign --force --sign "$SIGN_ID" --entitlements Resources/SnipClip.entitlements "$APP" 2>/dev/null; then
    codesign --force --sign "$SIGN_ID" "$APP"
fi
echo "→ $APP (signed: $SIGN_ID)"
