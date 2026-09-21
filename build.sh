#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/build/阿念.app"
CONTENTS_DIR="$APP_DIR/Contents"
EXECUTABLE_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -d "$COMPATIBLE_SDK" ]]; then
  SDK_PATH="$COMPATIBLE_SDK"
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
MODULE_CACHE="$PROJECT_DIR/build/module-cache"

mkdir -p "$EXECUTABLE_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0 \
  -O \
  "$PROJECT_DIR/阿念.swift" \
  -o "$EXECUTABLE_DIR/阿念" \
  -framework AppKit \
  -framework EventKit \
  -framework QuartzCore \
  -framework UserNotifications

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/sprite_sheet.png" "$RESOURCES_DIR/sprite_sheet.png"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/Resources/dog_pet_lines.json" "$RESOURCES_DIR/dog_pet_lines.json"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swift \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0 \
  "$PROJECT_DIR/validate_atlas.swift" \
  "$RESOURCES_DIR/sprite_sheet.png"

echo "构建完成：$APP_DIR"
