# ADR-0001: Space ordering and switching mechanism

- **Status:** Accepted
- **Date:** 2026-09-13
- **Context:** macOS 26.6.2 (Tahoe), Apple Silicon, Command Line Tools 26.6 (no Xcode)

## Context

The requirement: **⌘1 – ⌘9 switch to the Space at that position in the Mission Control
strip**, mixing Desktops and fullscreen apps freely, in the order the user sees them.

macOS provides no public Spaces API — not for enumerating Spaces, not for their order, and
not for switching to one. Every decision below is shaped by that.

Everything here was verified empirically on the target machine; measurements are quoted
rather than assumed, because several plausible-sounding approaches failed in ways that
only showed up under test.

---

## Decision 1: Read Space *order* from `CGSCopyManagedDisplaySpaces` (private, read-only)

Public sources were tried first and are provably wrong.

Captured simultaneously with a Mission Control screenshot:

```
Mission Control:  Desktop 1 | Desktop 2 | Slack | Chrome(Drive) | Desktop 3 | Pages | Chrome
com.apple.spaces: Desktop   | Chrome    | Desktop | Slack       | Desktop   | Pages | Chrome
```

Sources ruled out:

- `com.apple.spaces` → `Management Data.Monitors[].Spaces` — wrong, as above. Stable across
  Dock restarts and after disabling most-recent-use rearranging, so this is not staleness.
- `com.apple.spaces` → `Space Properties` — sorted by space id (`1, 3, 10, 13, 31, 47, 56`),
  not strip order.
- ⌃→ traversal to derive order — works, but races the switch animation and is far too
  disruptive to run on demand.

`CGSCopyManagedDisplaySpaces` returns `[1, 3, 56, 31, 13, 10, 47]`, matching both Mission
Control and a slow manual traversal exactly.

### The risk this knowingly accepts

The symbol is undocumented and Apple can change or remove it in any macOS release. Three
things bound that, and they are the reason this was judged acceptable rather than merely
convenient:

1. It is resolved via `dlsym` at runtime, never linked. A missing symbol degrades to the
   preference-file order; the app still launches and still switches Spaces, but fullscreen
   ordering may be wrong.
2. It is used **only to read**. Nothing private ever mutates system state.
3. The result is validated (non-empty, same id set as the fallback) before being trusted.

**Revisit if:** Apple ships a public Spaces API, or ⌘N ordering silently goes wrong after
an OS update — the fallback keeps the app working, which means a regression here is
*quiet*. That is the sharp edge: a broken symbol degrades to wrong-but-plausible ordering
rather than an obvious failure.

## Decision 2: Do **not** use `CGSManagedDisplaySetCurrentSpace` to switch

This would be the clean answer — one call, any Space, no stepping, no System Settings
dependency, and it scales to any number of Desktops. It was tested and rejected.

The call returned success (`0`) and the window server did change Space, but the UI did not
follow: windows from both the old and new Space were on screen simultaneously
(`93,180,2085,2287,2723,4249` merged with `2459,2462,2463,2464`). This is the known reason
yabai requires a scripting addition for Space focus. Recovering took several manual
switches.

Switching therefore uses public mechanisms only, accepting worse ergonomics (Decision 4)
in exchange for never leaving the window server in an inconsistent state.

## Decision 3: Drive macOS's own ⌃N shortcut for Desktops

No public API moves to a Desktop, and a Desktop has no app to activate. macOS's built-in
"Switch to Desktop N" is the closest public equivalent, so the app synthesises it.

Enabling those shortcuts programmatically does not work: writes to
`com.apple.symbolichotkeys` (ids 118–120) persisted to disk and survived `killall Dock`
twice, but ⌃3 still did nothing until the boxes were ticked in System Settings by hand.

So the app **reads** their state and tells the user which ones need enabling, in the menu
and in Settings, rather than silently doing nothing.

### Accepted drawback

A newly created Desktop arrives with its shortcut **unticked**, so adding a 4th Desktop
requires a manual step before ⌘N reaches it. This is surfaced in the UI, not hidden.

**Revisit if:** this becomes a frequent annoyance — the alternative is Decision 2, with its
cost.

## Decision 4: Reach ambiguous fullscreen Spaces by anchor-then-step

Where an app owns exactly one fullscreen Space, activating it jumps there instantly.

Where an app owns **several** — two Chrome windows in fullscreen — that fails, and there is
no public way to disambiguate:

- `NSRunningApplication.activate()` lands on whichever window was last focused.
- Accessibility cannot help either: `kAXWindowsAttribute` omits all but one fullscreen
  window of an application. Chrome reported AX windows `4184, 2463, 2462, 2459`; the second
  fullscreen Space's window (`208`) was absent entirely.

So those Spaces are reached with ⌃←/⌃→, jumping first to the nearest Desktop (a known
position) to shorten the path. Reaching position 7 from position 1 is six steps; from
Desktop 3 at position 5 it is two.

### Accepted drawback

**Intermediate Spaces are visible during the move.** For the layout this was built against
that is one or two slides. It cannot be removed without Decision 2. The user was shown this
trade-off explicitly and chose to keep the public implementation.

**Revisit if:** a layout appears where many Spaces sit far from any Desktop, making hops
long enough to be irritating.

## Decision 5: Pace stepping by `activeSpaceDidChangeNotification`, not fixed delays

Fixed delays failed in both directions: 0.6s dropped steps, and re-reading position too
early made the chain overshoot (requested position 6, landed on 7). macOS reports switch
completion directly, so each step waits for that notification, with a 1.4s timeout so a
dropped keystroke cannot hang the sequence.

Position is re-read before every step, so a dropped keystroke costs an extra step instead
of landing on the wrong Space.

## Decision 6: Four non-obvious requirements for synthesised keystrokes

Each of these was found by measurement, and each produced a *silent* failure — the event
posted successfully and was then ignored. Recorded because none is discoverable from
documentation.

1. **Post from the main thread.** From a background queue, `CGEvent.post` succeeds and the
   window server ignores it. Verified: three ⌃→ posted from a worker moved nothing; the
   same three from the main run loop moved three Spaces.
2. **Use `CGEventSource(stateID: .privateState)`.** `.hidSystemState` merges in physically
   held modifiers, so a ⌃→ synthesised while ⌘ is still down from the ⌘N press arrives as
   ⌘⌃→ and matches nothing.
3. **Arrow keys need `.maskNumericPad` and `.maskSecondaryFn`.** Real arrow events carry
   them and the Space shortcut will not match without them. This is why synthesised ⌃N
   (digits) worked while ⌃→ did not — the asymmetry that led to the cause.
4. **Hold the key ~50ms before releasing.** Posting keyDown and keyUp in the same instant
   made the shortcut matcher miss roughly four presses in five.

Plus: the app holds a `ProcessInfo.beginActivity` assertion during a step sequence.
Without it, App Nap throttles this background accessory app's scheduled work the moment
the Space switches away from it, and the chain stalls after one step.

## Decision 7: Build with `swiftc`, not SwiftPM

SwiftPM cannot run on this machine — `swift build` fails with a dyld symbol error inside
the Command Line Tools' own `swift-package` binary. The default SDK (`MacOSX27.0.sdk`,
Swift 6.4) is also newer than the installed compiler (6.3.3), which rejects it.

`Scripts/build-app.sh` drives `swiftc` directly against `MacOSX26.sdk` and assembles a
standard `.app` bundle. `Package.swift` is retained for Xcode later.

### Accepted drawback

The bundle is **ad-hoc signed**, so its code signature changes on every build and macOS
treats each build as a different app — **the Accessibility grant is invalidated by every
rebuild**. Documented in the README.

A self-signed code-signing certificate was tried as a fix (2026-09-13) and **did not
work**. The designated requirement did change from a content hash to
`identifier "com.prathambhatia.spaceswitcher" and certificate leaf = H"…"`, identical
across two builds — but installing a genuinely different binary signed by the same
certificate still lost the grant: ⌘1 and ⌘5 moved nothing until it was re-granted by hand.
The inspection looked convincing and the end-to-end test contradicted it, which is why the
test is the thing that counts.

Removed again rather than kept, since this app is not expected to change often and the
certificate, its keychain entry and the trust settings were all cost for no benefit.

**Revisit if:** rebuilds become frequent — but start from the end-to-end test, not from the
designated requirement.

## Alternatives rejected

- **Switching windows rather than Spaces** — the original brief. Built and working
  (CG↔AX matching by pid + frame, verified raising a specific Chrome window), then removed
  when the actual requirement turned out to be Spaces. Kept in git history only.
- **`_AXUIElementGetWindow`** to map AX windows to `CGWindowID` exactly. Resolves and works,
  but does not help: the window of the second fullscreen Space is not in the AX list at all,
  so an exact mapping has nothing to map.
- **Screen Recording permission** to read `kCGWindowName` and disambiguate fullscreen
  windows by title. Rejected: Sequoia/Tahoe re-prompt for that permission periodically, a
  poor trade for a background utility, and it would not fix the AX omission anyway.

## Consequences

- Ordering is correct and follows manual reordering, at the cost of one private read.
- Desktops and single-app fullscreen Spaces switch instantly.
- Fullscreen Spaces sharing an app slide through one or two intermediate Spaces.
- Three one-time system settings are required, two of which the app detects and reports.
- Every rebuild requires re-granting Accessibility.
