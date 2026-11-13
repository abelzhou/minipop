#!/bin/bash
set -e
cd "$(dirname "$0")"

VERSION="1.0.2"
APP="MiniPop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift -swift-version 6 make_icon.swift
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MiniPop</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.abel.MiniPop</string>
    <key>CFBundleName</key>
    <string>MiniPop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

swiftc -O -swift-version 6 -target arm64-apple-macosx13.0 main.swift -o "$APP/Contents/MacOS/MiniPop-arm64"
swiftc -O -swift-version 6 -target x86_64-apple-macosx13.0 main.swift -o "$APP/Contents/MacOS/MiniPop-x86_64"
lipo -create "$APP/Contents/MacOS/MiniPop-arm64" "$APP/Contents/MacOS/MiniPop-x86_64" -output "$APP/Contents/MacOS/MiniPop"
rm -f "$APP/Contents/MacOS/MiniPop-arm64" "$APP/Contents/MacOS/MiniPop-x86_64"

touch "$APP"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/MiniPop" --test
echo "Built $PWD/$APP (v${VERSION}, universal)"

if [[ "${1:-}" == "--dmg" ]]; then
    DMG="MiniPop-${VERSION}-macOS.dmg"
    STAGE=".dmg_stage"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "MiniPop ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Packaged $PWD/$DMG"
fi
