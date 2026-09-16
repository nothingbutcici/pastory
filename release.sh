#!/usr/bin/env bash
# Cut a GitHub release from the current tree: bump nothing here — set CFBundleShortVersionString in
# Resources/Info.plist first, commit, then run this. Uploads dist/Pastory-<version>.zip; the app's
# "检查更新" reads the latest release, so the tag must be v<version> and the asset must end in .zip.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
NOTES="${1:-}"
[ -n "$NOTES" ] || { echo "usage: ./release.sh <notes-file.md>"; exit 2; }
./dist.sh
git tag -a "v$VERSION" -m "Pastory $VERSION" 2>/dev/null || true
git push origin "v$VERSION"
gh release create "v$VERSION" "dist/Pastory-$VERSION.zip" --title "Pastory $VERSION" --notes-file "$NOTES"
echo "→ https://github.com/nothingbutcici/pastory/releases/tag/v$VERSION"
