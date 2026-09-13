#!/bin/bash
# Builds and runs the command-line Spaces diagnostic.
#   ./Scripts/diagnose.sh            list Spaces
#   ./Scripts/diagnose.sh go 3       switch to strip position 3
#   ./Scripts/diagnose.sh probe      fingerprint the current Space
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/diagnostics"
SDK="${SPACESWITCHER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
BIN="$BUILD/diagnose"

mkdir -p "$BUILD"

swiftc \
  -sdk "$SDK" \
  -swift-version 5 \
  -o "$BIN" \
  "$ROOT/Sources/SpaceSwitcher/Models/SpaceInfo.swift" \
  "$ROOT/Sources/SpaceSwitcher/Services/SpaceManager.swift" \
  "$ROOT/Sources/SpaceSwitcher/Utilities/PrivateSpaceAPI.swift" \
  "$ROOT/Sources/SpaceSwitcher/Utilities/Log.swift" \
  "$ROOT/Sources/SpaceSwitcher/Services/SpaceSwitcher.swift" \
  "$ROOT/Sources/SpaceSwitcher/Services/ScriptableWindows.swift" \
  "$ROOT/Sources/SpaceSwitcher/Services/SpaceWindowMemory.swift" \
  "$ROOT/Sources/SpaceSwitcher/Services/AccessibilityManager.swift" \
  "$ROOT/Diagnostics/main.swift"

exec "$BIN" "$@"
