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

    /// Watches for the permission being granted.
    ///
    /// macOS posts no notification for this, and the grant happens in System Settings
    /// rather than in our app, so polling is the only way to notice. It runs *only* while
    /// permission is missing and stops the moment it arrives — once granted there is
    /// nothing left to wait for, and a timer ticking forever in a background app earns
    /// its keep in neither correctness nor courtesy.
    ///
    /// Revocation is caught without polling: it is rare, and every switch checks
    /// `isTrusted` anyway, at which point monitoring is started again.
    public func startMonitoring() {
        guard pollTimer == nil, !isTrusted else { return }

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.isTrusted
            guard current != self.lastKnownState else { return }
            self.lastKnownState = current
            self.onChange?(current)
            if current { self.stopMonitoring() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
