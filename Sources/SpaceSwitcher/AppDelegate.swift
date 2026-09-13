import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let spaceManager = SpaceManager()
    private let accessibility = AccessibilityManager()
    private let hotkeys = HotkeyManager()
    private let loginItem = LoginItemManager()
    private lazy var switcher = SpaceSwitcher(spaceManager: spaceManager, accessibility: accessibility)

    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private var spaceObserver: NSObjectProtocol?
    private var registeredShortcuts = 0

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController(
            spaceManager: spaceManager,
            switcher: switcher,
            accessibility: accessibility
        )
        menuBar?.onOpenSettings = { [weak self] in self?.showSettings() }

        loginItem.enableUnlessUserDecided()

        registeredShortcuts = hotkeys.registerAll()
        Log.line("registered \(registeredShortcuts)/9 hotkeys, login item \(loginItem.isEnabled ? "on" : "off")")
        hotkeys.onShortcut = { [weak self] position in
            // The strip is re-read inside switchTo, so this reflects Spaces added or
            // removed since the last press.
            guard let self else { return }
            let outcome = self.switcher.switchTo(position: position)
            Log.line("⌘\(position) -> \(outcome)")
        }

        accessibility.onChange = { [weak self] _ in self?.settingsModel?.refresh() }
        accessibility.startMonitoring()

        spaceObserver = spaceManager.observeSpaceChanges { [weak self] in
            self?.settingsModel?.refresh()
        }

        if !accessibility.isTrusted {
            accessibility.requestAccess()
            showSettings()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregisterAll()
        accessibility.stopMonitoring()
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }

    private func showSettings() {
        if let settingsWindow {
            settingsModel?.refresh()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let model = SettingsModel(
            spaceManager: spaceManager,
            switcher: switcher,
            accessibility: accessibility,
            loginItem: loginItem,
            registeredShortcuts: registeredShortcuts
        )
        settingsModel = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Space Switcher"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
