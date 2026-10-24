#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/build/LockSleeve.app"
mkdir -p "$APP/Contents/MacOS" "$PWD/build/module-cache"
xcrun swiftc Sources/main.swift Sources/WallpaperStore.swift -o "$APP/Contents/MacOS/LockSleeve" -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework CoreImage -O
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LockSleeve</string>
<key>CFBundleIdentifier</key><string>local.lockalbum.app</string>
<key>CFBundleName</key><string>LockSleeve</string>
<key>CFBundleDisplayName</key><string>LockSleeve</string>
<key>CFBundleIconFile</key><string>AppIconMinimal</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>현재 재생 중인 곡의 제목과 앨범 표지를 읽어 앨범 배경을 만듭니다.</string>
</dict></plist>
PLIST
./scripts/build-icon.sh
mkdir -p "$APP/Contents/Resources"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIconMinimal.icns"
./scripts/build-extension.sh
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp ThirdParty/Phosphene-LICENSE "$APP/Contents/Resources/ThirdParty/Phosphene-LICENSE"
codesign --force --sign - "$APP"
print "빌드 완료: $APP"
