import Foundation
import ServiceManagement

/// Registers the app to launch at login.
///
/// Uses `SMAppService.mainApp`, the supported API since macOS 13 — it needs no helper
/// bundle and no launchd plist, and the user can revoke it in System Settings → General →
/// Login Items, which a hand-written LaunchAgent cannot offer.
///
/// Registration is tied to the app's location on disk. Moving the bundle invalidates it,
/// which is why `Scripts/install.sh` puts the app in /Applications rather than leaving it
/// in the build directory that every rebuild deletes.
public final class LoginItemManager {

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has explicitly disabled the login item in System Settings.
    /// Re-registering in that state would override a decision they made deliberately.
    public var isDeniedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    public func enable() -> Bool {
        guard !isEnabled else { return true }
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            Log.line("login item registration failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            Log.line("login item removal failed: \(error.localizedDescription)")
            return false
        }
    }

    private static let optedOutKey = "LaunchAtLoginDisabledByUser"

    /// Records that the user turned this off, so it is never silently switched back on.
    public var isOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: Self.optedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.optedOutKey) }
    }

    /// Registers at every launch unless the user opted out.
    ///
    /// Deliberately not a once-only flag: registration is bound to the bundle's location,
    /// so a copy launched from somewhere else — a build directory, a temporary folder —
    /// takes the registration with it and leaves a stale path behind that starts nothing.
    /// Re-asserting on launch makes the app on disk the one that wins.
    public func enableUnlessOptedOut() {
        guard !isOptedOut, !isEnabled else { return }
        if enable() {
            Log.line("login item registered for \(Bundle.main.bundleURL.path)")
        }
    }
}
