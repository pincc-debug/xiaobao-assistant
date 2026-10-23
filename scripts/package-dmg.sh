#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/dist/小保助教.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$PWD/dist/小保助教-$VERSION.dmg"
STAGING=$(mktemp -d "${TMPDIR:-/tmp/}live-assistant-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
codesign --verify --deep --strict "$APP"
ditto "$APP" "$STAGING/小保助教.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "小保助教 $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
print "$DMG"
