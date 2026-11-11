#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="MiniPop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift make_icon.swift
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset

cat > "$APP/Contents/Info.plist" << 'EOF'
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

swiftc -O main.swift -o "$APP/Contents/MacOS/MiniPop"
touch "$APP"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/MiniPop" --test
echo "Built $PWD/$APP"
