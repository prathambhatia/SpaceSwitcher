import AppKit
import ApplicationServices
import Foundation

/// Tracks Accessibility (TCC) authorisation, which window enumeration and focusing require.
public final class AccessibilityManager {

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private var pollTimer: Timer?
    private var lastKnownState: Bool

    /// Called on the main queue whenever authorisation flips.
    public var onChange: ((Bool) -> Void)?

    public init() {
        lastKnownState = AXIsProcessTrusted()
    }

    deinit { pollTimer?.invalidate() }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's one-time "allow Accessibility" prompt.
    public func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    /// Polls for authorisation changes — macOS posts no notification when TCC is granted,
    /// and the grant arrives while the user is in System Settings, not in our app.
    public func startMonitoring() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.isTrusted
            guard current != self.lastKnownState else { return }
            self.lastKnownState = current
            self.onChange?(current)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
