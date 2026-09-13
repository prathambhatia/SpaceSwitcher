#!/bin/bash
# Compiles SpaceSwitcher and wraps it in a standard .app bundle.
#
# Uses swiftc directly rather than `swift build` because this machine's SwiftPM
# cannot launch, and pins the SDK because the default (MacOSX27.0.sdk) is newer
# than the installed compiler. See README, "Toolchain note".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SpaceSwitcher"
BUNDLE_ID="com.prathambhatia.spaceswitcher"
OUT_DIR="${SPACESWITCHER_OUT:-$ROOT/build}"
APP="$OUT_DIR/$APP_NAME.app"
SDK="${SPACESWITCHER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"

if [[ ! -d "$SDK" ]]; then
  echo "error: SDK not found at $SDK" >&2
  echo "       set SPACESWITCHER_SDK to a valid macOS SDK path" >&2
  exit 1
fi

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (SDK: $(basename "$SDK"))"
# macOS ships bash 3.2, which has no mapfile.
SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/$APP_NAME" -name '*.swift' | sort)
swiftc \
  -sdk "$SDK" \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  "${SOURCES[@]}"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Window Switcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu-bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
# Ad-hoc signature. Note: this changes on every rebuild, which can invalidate the
# existing Accessibility grant — see README, "Rebuilding and Accessibility".
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "==> Built $APP"
echo
echo "Run it with:   open \"$APP\""
