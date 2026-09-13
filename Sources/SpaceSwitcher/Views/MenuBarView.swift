import AppKit
import Foundation

/// Owns the status-bar item and rebuilds its menu on demand.
///
/// AppKit rather than SwiftUI's `MenuBarExtra` because the contents are fully dynamic —
/// the Spaces strip is re-read every time the menu opens.
public final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let spaceManager: SpaceManager
    private let switcher: SpaceSwitcher
    private let accessibility: AccessibilityManager

    private var visibleSpaces: [SpaceInfo] = []

    public var onOpenSettings: (() -> Void)?

    public init(spaceManager: SpaceManager, switcher: SpaceSwitcher, accessibility: AccessibilityManager) {
        self.spaceManager = spaceManager
        self.switcher = switcher
        self.accessibility = accessibility
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.3.group",
                accessibilityDescription: "Space Switcher"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        visibleSpaces = spaceManager.spaces()
        let current = spaceManager.currentSpace(in: visibleSpaces)

        let header = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if visibleSpaces.isEmpty {
            let empty = NSMenuItem(title: "No Spaces detected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for space in visibleSpaces {
                menu.addItem(makeSpaceItem(space, isCurrent: current?.id == space.id))
            }
        }

        let missing = MissionControlShortcuts.desktopsMissingShortcuts(in: visibleSpaces)
        if !missing.isEmpty {
            menu.addItem(.separator())
            let warning = NSMenuItem(
                title: "⚠️ Desktop \(missing.map(String.init).joined(separator: ", ")) needs its shortcut enabled",
                action: #selector(openKeyboardSettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }

        if !accessibility.isTrusted {
            menu.addItem(.separator())
            let warning = NSMenuItem(
                title: "⚠️ Accessibility permission required",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Refresh Spaces", #selector(refresh), key: "r"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Space Switcher", #selector(quit), key: "q"))
    }

    private func makeSpaceItem(_ space: SpaceInfo, isCurrent: Bool) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(space.position). \(space.label)",
            action: #selector(switchToSpace(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = space.position
        item.state = isCurrent ? .on : .off

        if case .desktop(let ordinal) = space.kind,
           !MissionControlShortcuts.isDesktopShortcutEnabled(ordinal: ordinal) {
            item.toolTip = "Needs 'Switch to Desktop \(ordinal)' enabled in System Settings."
        }
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func switchToSpace(_ sender: NSMenuItem) {
        switcher.switchTo(position: sender.tag)
    }

    @objc private func refresh() {
        visibleSpaces = spaceManager.spaces()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openAccessibilitySettings() {
        accessibility.openSystemSettings()
    }

    @objc private func openKeyboardSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
