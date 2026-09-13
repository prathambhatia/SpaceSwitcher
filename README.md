# SpaceSwitcher

A macOS menu-bar utility that binds **⌘1 – ⌘9** to the Spaces in your Mission Control
strip, in the order you actually see them — Desktops and fullscreen apps mixed freely.

```
⌘1          ⌘2          ⌘3      ⌘4              ⌘5          ⌘6      ⌘7
Desktop 1 │ Desktop 2 │ Slack │ Chrome (Drive) │ Desktop 3 │ Pages │ Chrome (GitHub)
```

macOS can only do part of this on its own: its built-in shortcuts cover Desktops but not
fullscreen apps, and they number Desktops separately from their position on screen. This
gives you one continuous numbering across everything, re-read on every keypress, so it
follows along when you add, remove or drag Spaces around.

---

## Install

One command. Nothing else to download.

```bash
curl -fsSL https://raw.githubusercontent.com/prathambhatia/SpaceSwitcher/main/install.sh | bash
```

It builds from source, installs to `/Applications`, sets itself to start at login, and
opens the one System Settings pane you need.

**Requirements:** macOS 14 or later, and Xcode Command Line Tools. If you do not have the
tools, run `xcode-select --install` first — the installer will tell you if they are
missing.

### The one manual step

macOS does not allow an app to grant itself Accessibility permission, so you have to do
this once:

> **System Settings → Privacy & Security → Accessibility** → add
> `/Applications/SpaceSwitcher.app` and switch it on.

The installer opens that pane for you. Nothing else is required — ⌘1–⌘9 work immediately
afterwards, and keep working after a restart.

### Optional: make Desktop switching instant

Everything works without this. But macOS has built-in "Switch to Desktop N" shortcuts that
jump to a Desktop with no animation, and SpaceSwitcher will use them when they are on:

> **System Settings → Keyboard → Keyboard Shortcuts… → Mission Control** → expand the
> nested **Mission Control** group → tick **Switch to Desktop 1 / 2 / 3 …**

Without them, Desktops are reached by sliding across intermediate Spaces instead — correct,
just slower. A newly created Desktop always starts without one, which is why this is a
speed setting and never a requirement.

### Uninstall

```bash
rm -rf /Applications/SpaceSwitcher.app
defaults delete com.apple.dock mru-spaces && killall Dock   # restore auto-rearranging
```

Then remove it from System Settings → General → Login Items, and from Accessibility.

---

## How it works

Three mechanisms, because no single one reaches every kind of Space.

| Space | How it is reached | Instant? |
|---|---|---|
| Desktop, with macOS's shortcut enabled | macOS's own ⌃N | yes |
| Desktop, without it | slide with ⌃←/⌃→ | no |
| Fullscreen app, the only Space that app owns | activate the app | yes |
| Fullscreen app owning several Spaces, once learned | raise that window via Apple Events | yes |
| Fullscreen app owning several Spaces, first time | slide with ⌃←/⌃→, then remember | no |

The last row is the interesting one. Two fullscreen windows of the same app — two Chrome
windows, say — cannot be told apart by any public means: `activate()` lands on whichever
was focused last, and Accessibility is no help either, because `kAXWindowsAttribute` omits
all but one fullscreen window of an application. `⌃←/⌃→` is macOS's own "move one Space
over" command, so intermediate Spaces are visible when sliding. SpaceSwitcher shortens the
trip by jumping to the nearest Desktop first, which usually leaves only a step or two.

Sliding re-reads the strip before every step and tracks its target by Space id rather than
position, so creating a Desktop mid-move cannot make it land somewhere else.

### Learning to jump instantly

Two fullscreen windows of one app cannot be told apart by any public means — but an app's
own AppleScript interface does see them all, and raising a window moves the display to its
Space. There is no way to ask "which window is on Space N", so it is learned: the first
time such a Space is reached by sliding, the window left in front is recorded against it,
and every later press raises that window directly and arrives at once.

macOS asks permission the first time (to let SpaceSwitcher control that app). The entry is
only a cache — if the window is closed or moved, raising fails, and it slides once more and
re-learns. Apps without an AppleScript interface, such as most Electron apps, keep sliding,
though those almost always own a single fullscreen Space and are already instant.

### Why automatic Space rearranging gets turned off

The installer runs:

```bash
defaults write com.apple.dock mru-spaces -bool false
```

This is the **"Automatically rearrange Spaces based on most recent use"** setting in
System Settings → Desktop & Dock → Mission Control. With it on, macOS reshuffles your
Spaces as you work, so ⌘3 would mean something different minute to minute. With it off you
still set the order yourself by dragging in Mission Control, and ⌘N follows.

---

## Known limitations

- **Sliding is visible** the first time a same-app fullscreen Space is used, and every
  time for apps with no AppleScript interface.
- **Empty Desktops** cannot be identified from window contents alone. Position normally
  comes straight from the window server, which does identify them; only the fallback path
  is affected.
- **Ghost Spaces** are left in macOS's preference file when a fullscreen window closes.
  They are filtered out against the live window list, so they do not shift your numbering.
- **A Split View Space whose partner app quit** may ignore activation. This is detected and
  falls back to sliding.
- **Rebuilding invalidates the Accessibility grant.** macOS matches the grant against the
  app's code signature, and ad-hoc signing makes that a hash of the contents, so every
  build looks like a new app. After rebuilding, remove SpaceSwitcher from Accessibility
  with `−` and add it again. This only affects people who rebuild; installing once and
  granting once is unaffected.

---

## Building from source

```bash
git clone https://github.com/prathambhatia/SpaceSwitcher.git
cd SpaceSwitcher
./Scripts/install.sh     # build, install to /Applications, launch
```

Or just build without installing:

```bash
./Scripts/build-app.sh   # produces build/SpaceSwitcher.app
```

### Diagnostics

```bash
./Scripts/diagnose.sh          # list Spaces and how each would be reached
./Scripts/diagnose.sh go 4     # switch to strip position 4 and report the result
./Scripts/diagnose.sh probe    # fingerprint the current Space
```

The app logs hotkey registration and every switch to stderr, visible if you run the binary
directly:

```bash
/Applications/SpaceSwitcher.app/Contents/MacOS/SpaceSwitcher
```

### Layout

```
Sources/SpaceSwitcher/
├── SpaceSwitcherApp.swift        @main entry point
├── AppDelegate.swift             wiring, lifecycle
├── Models/SpaceInfo.swift        one tile in the strip
├── Services/
│   ├── SpaceManager.swift        reads and orders the strip
│   ├── SpaceSwitcher.swift       moves between Spaces
│   ├── HotkeyManager.swift       ⌘1–⌘9 registration
│   ├── LoginItemManager.swift    start at login
│   └── AccessibilityManager.swift
├── Views/                        menu bar + settings
└── Utilities/                    ordering source, logging
```

### Toolchain note

The build uses `swiftc` directly rather than SwiftPM, and probes for an SDK the installed
compiler accepts. This is deliberate: a Command Line Tools install can ship an SDK newer
than its own compiler, and some have a broken `swift-package` binary that cannot launch at
all. `Package.swift` is kept so the project opens in Xcode, but it is not the build path.

Override the SDK with `SPACESWITCHER_SDK=/path/to/MacOSX.sdk` if you need to.

---

## Design notes

Space *ordering* is the one thing that requires a private call — no public API reports the
Mission Control order, and the obvious candidates are provably wrong. It is resolved at
runtime with `dlsym`, used only for reading, and falls back to a public source if it ever
disappears. Everything that changes state is public API.

`docs/adr/0001-space-ordering-and-switching.md` records the evidence behind each decision,
the drawbacks knowingly accepted, and the alternatives that were tested and rejected —
including a direct private "jump to Space" call that left the window server in an
inconsistent state.
