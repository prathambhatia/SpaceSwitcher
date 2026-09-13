import AppKit
import CoreGraphics
import Foundation

// Command-line diagnostic for the Spaces strip. Not part of the .app bundle.
//
//   diagnose            list Spaces and shortcut readiness
//   diagnose go N       switch to strip position N
//   diagnose probe      print a fingerprint of the current Space (for switch testing)

let spaceManager = SpaceManager()
let accessibility = AccessibilityManager()
let switcher = SpaceSwitcher(spaceManager: spaceManager, accessibility: accessibility)

/// Identifies the current Space well enough to tell whether a switch happened.
func fingerprint() -> String {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return "none"
    }
    let ids = raw
        .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        .sorted()
    return ids.map(String.init).joined(separator: ",")
}

func list() {
    let spaces = spaceManager.spaces()
    let current = spaceManager.currentSpace(in: spaces)

    print("Accessibility trusted: \(accessibility.isTrusted)")
    print("Spaces in Mission Control order: \(spaces.count)\n")
    print(" ⌘N  KIND         READY  LABEL")
    print(String(repeating: "-", count: 64))

    for space in spaces {
        let marker = (current?.id == space.id) ? "*" : " "
        var kind = "Desktop"
        var ready = "yes"
        if case .desktop(let ordinal) = space.kind {
            kind = "Desktop \(ordinal)"
            ready = MissionControlShortcuts.isDesktopShortcutEnabled(ordinal: ordinal) ? "yes" : "NO ⌃\(ordinal)"
        } else {
            kind = "Fullscreen"
        }
        print(
            "\(marker)⌘\(space.position)  "
                + kind.padding(toLength: 12, withPad: " ", startingAt: 0)
                + " \(ready.padding(toLength: 6, withPad: " ", startingAt: 0))"
                + " \(space.label)"
        )
    }

    let missing = MissionControlShortcuts.desktopsMissingShortcuts(in: spaces)
    if !missing.isEmpty {
        print("\nDesktops without an enabled shortcut: \(missing.map(String.init).joined(separator: ", "))")
        print("Enable them in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.")
    }
    print("\n(* = current Space, blank if it cannot be identified — empty Desktops are ambiguous)")
}

let arguments = CommandLine.arguments
switch arguments.count >= 2 ? arguments[1] : "list" {
case "probe":
    print(fingerprint())

case "go":
    guard arguments.count >= 3, let position = Int(arguments[2]) else {
        print("usage: diagnose go N")
        exit(2)
    }
    _ = fingerprint()

    func report(_ space: SpaceInfo, settle: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        let arrived = spaceManager.isCurrent(space)
        print(arrived ? "RESULT: arrived" : "RESULT: did NOT arrive (now \(fingerprint()))")
    }

    switch switcher.switchTo(position: position) {
    case .switched(let space):
        print("Requested ⌘\(position) -> \(space.label)")
        report(space, settle: 2.5)
    case .navigating(let space, let steps):
        print("Requested ⌘\(position) -> \(space.label) (navigating \(steps) step(s))")
        report(space, settle: 2.0 + Double(max(steps, 1)) * 1.3)
    case .noSuchSpace(let position, let available):
        print("No Space at position \(position) (only \(available) exist)")
    case .desktopShortcutUnavailable(let space, let ordinal):
        print("\(space.label) has no enabled ⌃\(ordinal) shortcut — tick it in System Settings.")
    case .unreachable(let space):
        print("\(space.label) cannot be reached with public APIs.")
    case .accessibilityRequired:
        print("Accessibility permission required to synthesise the Desktop shortcut.")
    }

default:
    list()
}
