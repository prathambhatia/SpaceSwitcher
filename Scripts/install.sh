#!/bin/bash
# Builds SpaceSwitcher and installs it to /Applications, then launches it.
#
# Installing matters: build-app.sh deletes build/ on every run, so an app left there
# would break its own login item the next time you rebuild. /Applications is stable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SpaceSwitcher"
DEST_DIR="${SPACESWITCHER_DEST:-/Applications}"
DEST="$DEST_DIR/$APP_NAME.app"

"$ROOT/Scripts/build-app.sh"

if [[ ! -w "$DEST_DIR" ]]; then
  echo "error: $DEST_DIR is not writable" >&2
  echo "       re-run with SPACESWITCHER_DEST=\"\$HOME/Applications\"" >&2
  exit 1
fi

echo "==> Installing to $DEST"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST"

echo "==> Launching"
open "$DEST"
sleep 2

cat <<EOF

Installed: $DEST

The app registers itself as a login item on first launch, so it will start
automatically after a restart.

If this is a fresh install path, grant Accessibility once:
  System Settings > Privacy & Security > Accessibility > + > $DEST

macOS ties that permission to the app's location and signature, so granting it
for this copy is what makes it stick across restarts.
EOF
