#!/usr/bin/env bash
# Build fast-whisper.app using Command Line Tools (swiftc), without Xcode.
# make app builds and installs the application.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
APP="build/fast-whisper.app"
BUNDLE_ID="com.fastwhisper.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
while IFS= read -r source; do SOURCES+=("$source"); done < <(find Sources -name '*.swift' -type f | sort)

swiftc -O -swift-version 5 -module-cache-path build/ModuleCache \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework Carbon \
  "${SOURCES[@]}" -o "$APP/Contents/MacOS/fast-whisper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>fast-whisper</string>
  <key>CFBundleDisplayName</key><string>fast-whisper</string>
  <key>CFBundleExecutable</key><string>fast-whisper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>fast-whisper записывает речь, чтобы распознать её локальной моделью Whisper. Звук не покидает этот Mac.</string>
  <key>FWProjectRoot</key><string>${ROOT}</string>
</dict>
</plist>
PLIST

# Ad-hoc signing is required for macOS to remember microphone permission.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null
echo "✓ built: $ROOT/$APP"
