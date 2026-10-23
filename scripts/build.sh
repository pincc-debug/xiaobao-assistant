#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CONFIGURATION="${BUILD_CONFIGURATION:-release}"
if [[ ! -f Sources/Assistant/Resources/AppIcon.icns || assets/icon/AppIcon-source.png -nt Sources/Assistant/Resources/AppIcon.icns ]]; then
    ./scripts/make-icon.sh
fi
swift build -c "$CONFIGURATION"
mkdir -p "$PWD/dist"
STAGING=$(mktemp -d "$PWD/dist/.build-app.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/小保助教.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIGURATION/LiveAssistant" "$APP/Contents/MacOS/LiveAssistant"
python3 scripts/bundle-ffmpeg.py "$APP"
for resource in .build/$CONFIGURATION/*.bundle; do cp -R "$resource" "$APP/Contents/Resources/"; done
# SwiftPM may retain old resource output during incremental builds. Keep the icon once.
for bundle in "$APP/Contents/Resources/"*.bundle; do
    rm -f "$bundle/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
done
cp Sources/Assistant/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ "$CONFIGURATION" == "release" ]]; then
    python3 scripts/optimize-png.py "$APP/Contents/Resources"
    /usr/bin/strip -S -x "$APP/Contents/MacOS/LiveAssistant"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LiveAssistant</string>
<key>CFBundleIdentifier</key><string>org.local.LiveAssistant</string>
<key>CFBundleName</key><string>小保助教</string>
<key>CFBundleDisplayName</key><string>小保助教</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>48</string>
<key>CFBundleShortVersionString</key><string>0.1.19</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>助教课程资料</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Owner</string><key>CFBundleTypeExtensions</key><array><string>xblesson</string></array></dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSMicrophoneUsageDescription</key><string>点击语音按钮时，将你的口述转换为助教指令或回答。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Replace only after the fresh staging bundle has passed signing verification.
if [[ -d "$PWD/dist/小保助教.app" ]]; then
    mv "$PWD/dist/小保助教.app" "$STAGING/previous.app"
fi
if ! mv "$APP" "$PWD/dist/小保助教.app"; then
    if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$PWD/dist/小保助教.app"; fi
    exit 1
fi
print "$PWD/dist/小保助教.app"
