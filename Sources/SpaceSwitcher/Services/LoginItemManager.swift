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

    /// Registers on first run so the app starts at login without the user doing anything,
    /// while still honouring a later decision to turn it off.
    public func enableUnlessUserDecided() {
        let key = "LoginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if enable() {
            UserDefaults.standard.set(true, forKey: key)
            Log.line("login item registered")
        }
    }
}
