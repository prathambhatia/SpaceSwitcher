#!/bin/bash
# Compiles SpaceSwitcher and wraps it in a standard .app bundle.
#
# Uses swiftc directly rather than `swift build` so it works on machines where the
# Command Line Tools' SwiftPM is broken. See README, "Toolchain note".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SpaceSwitcher"
BUNDLE_ID="com.prathambhatia.spaceswitcher"
OUT_DIR="${SPACESWITCHER_OUT:-$ROOT/build}"
APP="$OUT_DIR/$APP_NAME.app"

# Picks an SDK the installed compiler can actually parse.
#
# Normally the default SDK is correct and no -sdk flag is needed. But a Command Line Tools
# install can end up carrying an SDK newer than its own compiler (e.g. MacOSX27 with Swift
# 6.3), and swiftc then rejects the standard library outright. Probing avoids hardcoding a
# path that only suits one machine.
select_sdk() {
  if [[ -n "${SPACESWITCHER_SDK:-}" ]]; then
    echo "$SPACESWITCHER_SDK"
    return
  fi

  local probe
  probe="$(mktemp -t spaceswitcher_probe).swift"
  printf 'import AppKit\nlet _ = NSApplication.shared\n' > "$probe"

  if swiftc -typecheck "$probe" >/dev/null 2>&1; then
    rm -f "$probe"
    echo ""  # default SDK works
    return
  fi

  local candidate
  for candidate in $(ls -d \
      "$(xcode-select -p 2>/dev/null)"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk \
      /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk \
      2>/dev/null | sort -rV); do
    if swiftc -sdk "$candidate" -typecheck "$probe" >/dev/null 2>&1; then
      rm -f "$probe"
      echo "$candidate"
      return
    fi
  done

  rm -f "$probe"
  echo "NONE"
}

SDK="$(select_sdk)"
if [[ "$SDK" == "NONE" ]]; then
  echo "error: no macOS SDK works with the installed Swift compiler" >&2
  echo "       try: xcode-select --install   (or install Xcode)" >&2
  exit 1
fi

SDK_ARGS=()
[[ -n "$SDK" ]] && SDK_ARGS=(-sdk "$SDK")

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling${SDK:+ (SDK: $(basename "$SDK"))}"
# macOS ships bash 3.2, which has no mapfile.
SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/$APP_NAME" -name '*.swift' | sort)

swiftc \
  "${SDK_ARGS[@]}" \
  -swift-version 5 \
  -O \
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
    <key>CFBundleName</key><string>SpaceSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu-bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>SpaceSwitcher raises a specific window to jump straight to the Space it occupies.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
# Ad-hoc. The signature is a hash of the contents, so a rebuild invalidates the
# Accessibility grant and it has to be granted again — see README.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "==> Built $APP"
