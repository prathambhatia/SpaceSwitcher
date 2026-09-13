import AppKit
import SwiftUI

public final class SettingsModel: ObservableObject {
    @Published public var isTrusted: Bool
    @Published public var registeredShortcuts: Int
    @Published public var spaces: [SpaceInfo] = []
    @Published public var desktopsMissingShortcuts: [Int] = []

    @Published public var launchAtLogin: Bool

    private let spaceManager: SpaceManager
    private let switcher: SpaceSwitcher
    private let accessibility: AccessibilityManager
    private let loginItem: LoginItemManager

    public init(
        spaceManager: SpaceManager,
        switcher: SpaceSwitcher,
        accessibility: AccessibilityManager,
        loginItem: LoginItemManager,
        registeredShortcuts: Int
    ) {
        self.spaceManager = spaceManager
        self.switcher = switcher
        self.accessibility = accessibility
        self.loginItem = loginItem
        self.isTrusted = accessibility.isTrusted
        self.registeredShortcuts = registeredShortcuts
        self.launchAtLogin = loginItem.isEnabled
    }

    public func refresh() {
        isTrusted = accessibility.isTrusted
        spaces = spaceManager.spaces()
        desktopsMissingShortcuts = MissionControlShortcuts.desktopsMissingShortcuts(in: spaces)
        launchAtLogin = loginItem.isEnabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        // Remembered so the launch-time re-assert cannot silently undo this choice.
        loginItem.isOptedOut = !enabled
        _ = enabled ? loginItem.enable() : loginItem.disable()
        launchAtLogin = loginItem.isEnabled
    }

    public func openSystemSettings() { accessibility.openSystemSettings() }

    public func openKeyboardSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        )
    }

    public func switchTo(_ space: SpaceInfo) { switcher.switchTo(space) }
}

public struct SettingsView: View {
    @ObservedObject private var model: SettingsModel

    public init(model: SettingsModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionSection
            if !model.desktopsMissingShortcuts.isEmpty {
                Divider()
                desktopShortcutSection
            }
            Divider()
            spacesSection
        }
        .padding(20)
        .frame(width: 480, height: 560)
        .onAppear { model.refresh() }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                model.isTrusted ? "Accessibility permission granted" : "Accessibility permission required",
                systemImage: model.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(model.isTrusted ? Color.green : Color.orange)
            .font(.headline)

            Text("⌘1 – ⌘9 switch to the Space at that position in Mission Control.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(
                "Launch at login",
                isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
            )
            .toggleStyle(.checkbox)

            if !model.isTrusted {
                Text("Needed to send the Desktop-switch keystroke. Fullscreen Spaces work without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security Settings…") { model.openSystemSettings() }
            }
        }
    }

    private var desktopShortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Optional: faster Desktop switching", systemImage: "hare")
                .foregroundStyle(.secondary)
                .font(.headline)

            Text(
                "Desktop \(model.desktopsMissingShortcuts.map(String.init).joined(separator: ", ")) "
                    + "is reached by sliding across the Spaces in between. Enabling macOS's own "
                    + "\"Switch to Desktop\" shortcut makes it jump instantly instead. "
                    + "Everything works without this."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("System Settings → Keyboard → Keyboard Shortcuts… → Mission Control → expand Mission Control.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Keyboard Settings…") { model.openKeyboardSettings() }
        }
    }

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spaces").font(.headline)
                Spacer()
                Button("Refresh") { model.refresh() }
            }

            if model.spaces.isEmpty {
                Text("No Spaces detected.").font(.callout).foregroundStyle(.secondary)
            } else {
                List(model.spaces) { space in
                    HStack(spacing: 10) {
                        Text("⌘\(space.position)")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 34, alignment: .leading)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(space.label).lineLimit(1)
                            Text(space.isDesktop ? "Desktop" : "Fullscreen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.switchTo(space) }
                }
                .listStyle(.inset)
            }
        }
    }
}
