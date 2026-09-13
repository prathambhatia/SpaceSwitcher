# SpaceSwitcher

A menu-bar utility that binds **⌘1 – ⌘9** to the Spaces in your Mission Control strip, in
the order you see them — Desktops and fullscreen apps mixed freely.

```
⌘1          ⌘2          ⌘3      ⌘4              ⌘5          ⌘6      ⌘7
Desktop 1 │ Desktop 2 │ Slack │ Chrome (Drive) │ Desktop 3 │ Pages │ Chrome (GitHub)
```

The mapping is re-read on every keypress, so it follows the strip as you add, remove or
drag Spaces around in Mission Control.

## Requirements

- macOS 14+ (developed and tested on macOS 26 Tahoe, Apple Silicon)
- Accessibility permission
- Three one-time system settings (below)

## Build

```bash
./Scripts/build-app.sh      # produces build/SpaceSwitcher.app
open build/SpaceSwitcher.app
```

There is no Xcode dependency — see *Toolchain note*.

## Setup

### 1. Accessibility permission

System Settings → Privacy & Security → Accessibility → enable **SpaceSwitcher**.

Needed to synthesise the keystrokes that move between Spaces. Without it, only fullscreen
Spaces reachable by activating their app will work.

### 2. "Switch to Desktop N" shortcuts

System Settings → Keyboard → Keyboard Shortcuts… → **Mission Control** → expand the nested
**Mission Control** group → tick **Switch to Desktop 1 / 2 / 3**.

macOS exposes no public API for moving to a Desktop, so the app drives macOS's own
shortcut. These are **off by default**, and a newly created Desktop arrives unticked — the
app detects this and shows which ones need enabling, in the menu and in Settings.

These cannot be enabled programmatically: writes to `com.apple.symbolichotkeys` land on
disk but the Dock ignores them, verified on macOS 26 across two Dock restarts.

### 3. Turn off automatic Space rearranging

System Settings → Desktop & Dock → Mission Control → untick **Automatically rearrange
Spaces based on most recent use**.

```bash
defaults write com.apple.dock mru-spaces -bool false && killall Dock
```

With this on, macOS reorders your Spaces as you use them, so ⌘3 means something different
minute to minute. You still control the order yourself by dragging in Mission Control.

## How a Space is reached

Three mechanisms, because no single one reaches every kind of Space.

| Space | Mechanism | Instant? |
|---|---|---|
| Desktop | macOS's ⌃N "Switch to Desktop N" | yes |
| Fullscreen, sole Space owned by its app | activate the app | yes |
| Fullscreen, app owns several | jump to nearest Desktop, then ⌃←/⌃→ | no — 1–2 visible steps |

The third case exists because two fullscreen windows of one app (two Chrome windows, say)
cannot be told apart: `activate()` lands on whichever was last focused, and Accessibility
cannot disambiguate either — `kAXWindowsAttribute` omits all but one fullscreen window of
an app. `⌃←/⌃→` is macOS's own "move one Space over" command, so intermediate Spaces are
unavoidable there. The app minimises it by anchoring on the closest Desktop first, which
bounds a typical hop to one or two steps.

## Known limitations

- **Stepping is visible** for fullscreen Spaces whose app owns more than one, as above.
- **Empty Desktops are ambiguous** to window-state inspection. Position is normally read
  from the window server directly, which does identify them; the fallback path cannot.
- **A ghost Space** is left in the preference file when a fullscreen window closes. These
  are filtered out by checking each Space's window against the live window list, so they
  do not shift the ⌘N numbering.
- **A Split View Space whose partner app has quit** may not respond to activation. The app
  detects the failure and falls back to stepping.
- **Rebuilding invalidates the Accessibility grant.** The bundle is ad-hoc signed, so its
  code signature changes on every build and macOS treats it as a different app. After a
  rebuild, remove SpaceSwitcher from the Accessibility list with `−` and add it again.

## Design notes

Ordering is the one thing that needs a private call. See
`Sources/SpaceSwitcher/Utilities/PrivateSpaceAPI.swift` and
`docs/adr/0001-space-ordering-and-switching.md` for the evidence that no public source
reports the true strip order, and for the bounds placed on that risk. Everything that
*changes* state is public API.

## Project layout

```
Sources/SpaceSwitcher/
├── SpaceSwitcherApp.swift        @main entry point
├── AppDelegate.swift             wiring, lifecycle
├── Models/SpaceInfo.swift        one tile in the strip
├── Services/
│   ├── SpaceManager.swift        reads and orders the strip
│   ├── SpaceSwitcher.swift       moves between Spaces
│   ├── HotkeyManager.swift       ⌘1–⌘9 registration
│   └── AccessibilityManager.swift
├── Views/                        menu bar + settings
└── Utilities/                    ordering source, logging
Diagnostics/                      CLI for inspecting and testing, not shipped
Scripts/                          build + diagnose
```

## Diagnostics

```bash
./Scripts/diagnose.sh            # list Spaces, show which shortcuts are ready
./Scripts/diagnose.sh go 4       # switch to strip position 4 and report
./Scripts/diagnose.sh probe      # fingerprint the current Space
```

The app logs hotkey registration and every switch outcome to stderr:

```bash
./build/SpaceSwitcher.app/Contents/MacOS/SpaceSwitcher
```

## Toolchain note

This machine cannot run SwiftPM: `swift build` fails with a dyld symbol error inside the
Command Line Tools' own `swift-package` binary, and the default SDK (`MacOSX27.0.sdk`,
built with Swift 6.4) is newer than the installed compiler (6.3.3), so `swiftc` rejects it
too.

`Scripts/build-app.sh` therefore drives `swiftc` directly and pins `MacOSX26.sdk`. Override
with `SPACESWITCHER_SDK=/path/to/SDK` if your setup differs.

`Package.swift` is kept so the project opens in Xcode once it is installed; it is not the
working build path today.
