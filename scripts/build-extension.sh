#!/bin/zsh
set -eu
cd "${0:A:h}/.."
xcodebuild -project LockAlbumExtension.xcodeproj -target LockAlbumWallpaper -configuration Release CONFIGURATION_BUILD_DIR="$PWD/build/xcode-extension" OBJROOT="$PWD/build/xcode-obj" SYMROOT="$PWD/build/xcode-products" > "$PWD/build/extension-xcode-build.log" 2>&1 || { tail -50 "$PWD/build/extension-xcode-build.log"; exit 1; }
mkdir -p "$PWD/build/LockSleeve.app/Contents/Extensions"
ditto "$PWD/build/xcode-extension/LockAlbumWallpaper.appex" "$PWD/build/LockSleeve.app/Contents/Extensions/LockAlbumWallpaper.appex"
codesign --force --sign - "$PWD/build/LockSleeve.app"
