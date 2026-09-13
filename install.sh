#!/bin/bash
#
# One-line installer for SpaceSwitcher.
#
#   curl -fsSL https://raw.githubusercontent.com/prathambhatia/SpaceSwitcher/main/install.sh | bash
#
# Downloads the source, builds it, installs to /Applications, registers it to start at
# login, and opens the two System Settings panes that need a manual tick.
set -euo pipefail

REPO_URL="${SPACESWITCHER_REPO:-https://github.com/prathambhatia/SpaceSwitcher.git}"
BRANCH="${SPACESWITCHER_BRANCH:-main}"
APP_NAME="SpaceSwitcher"
DEST_DIR="${SPACESWITCHER_DEST:-/Applications}"
DEST="$DEST_DIR/$APP_NAME.app"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

bold "SpaceSwitcher installer"
echo

# --- checks -----------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only."

major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "needs macOS 14 or later (found $(sw_vers -productVersion))."

# Xcode Command Line Tools supply both swiftc and git. If they are missing, install them
# rather than asking the user to go away and come back.
if ! swiftc --version >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  bold "Xcode Command Line Tools are required — installing them now."
  echo "A system dialog will appear. Click Install and accept the licence;"
  echo "this script waits and continues on its own."
  echo

  # Returns immediately and does the work in Apple's own installer UI. Already-running or
  # already-installed both exit non-zero, so the wait loop below is what actually decides.
  xcode-select --install >/dev/null 2>&1 || true

  waited=0
  until swiftc --version >/dev/null 2>&1 && command -v git >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge 1800 ]; then
      fail "Command Line Tools did not finish installing. Run 'xcode-select --install' and try again."
    fi
    if [ $((waited % 60)) -eq 0 ]; then
      echo "    still waiting... (${waited}s)"
    fi
  done
  echo "    Command Line Tools ready."
  echo
fi

[[ -w "$DEST_DIR" ]] || fail "$DEST_DIR is not writable. Re-run with SPACESWITCHER_DEST=\"\$HOME/Applications\""

# --- fetch and build --------------------------------------------------------

WORK="$(mktemp -d -t spaceswitcher)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading"
git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK/src" \
  || fail "could not clone $REPO_URL (is the repository public?)"

echo "==> Building"
"$WORK/src/Scripts/build-app.sh" >/dev/null || fail "build failed. Re-run Scripts/build-app.sh in $WORK/src to see why."

echo "==> Installing to $DEST"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$WORK/src/build/$APP_NAME.app" "$DEST"

# --- system settings the app depends on -------------------------------------

# With this on, macOS reorders Spaces by recent use, so a fixed number would point at a
# different Space minute to minute. Revert any time with:
#   defaults delete com.apple.dock mru-spaces && killall Dock
if [[ "$(defaults read com.apple.dock mru-spaces 2>/dev/null || echo 1)" != "0" ]]; then
  echo "==> Disabling automatic Space rearranging (required for stable numbering)"
  defaults write com.apple.dock mru-spaces -bool false
  killall Dock 2>/dev/null || true
  sleep 3
fi

echo "==> Launching"
open "$DEST"
sleep 2

# --- what the user still has to do ------------------------------------------

cat <<EOF

$(bold "Installed: $DEST")
It is registered to start automatically at login.

$(bold "One manual step remains — macOS does not allow an app to grant itself this:")

  1. Accessibility permission
     System Settings > Privacy & Security > Accessibility
     Add $DEST and switch it on.

Then press Cmd-1, Cmd-2, ... to jump to Spaces in Mission Control order.

Optional, for instant Desktop jumps instead of a short slide:
  System Settings > Keyboard > Keyboard Shortcuts... > Mission Control
  Expand the nested "Mission Control" group and tick "Switch to Desktop 1", "2", ...
  Everything works without this.

Opening Accessibility now.
EOF

sleep 2
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
