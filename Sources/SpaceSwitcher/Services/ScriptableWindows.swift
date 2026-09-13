import AppKit
import Foundation

/// Raises a specific window of a scriptable application via Apple Events.
///
/// This exists to solve one problem: when an app owns several fullscreen Spaces, macOS
/// offers no public way to reach a chosen one. `activate()` lands on whichever window was
/// focused last, and Accessibility omits all but one fullscreen window of an app. An app's
/// own AppleScript interface does see them all, and raising a window moves the display to
/// the Space that window lives on.
///
/// Only applies to apps that expose windows to AppleScript — Chrome and Safari do, most
/// Electron apps do not. Callers must treat failure as normal and fall back.
public enum ScriptableWindows {

    /// Identifier of the app's frontmost window, or nil if the app is not scriptable.
    public static func frontWindowID(bundleID: String) -> Int? {
        let source = """
        tell application id "\(bundleID)" to return id of front window
        """
        guard let value = run(source) else { return nil }
        return value.int32Value == 0 ? Int(value.stringValue ?? "") : Int(value.int32Value)
    }

    /// Brings `windowID` to the front, which switches to the Space it occupies.
    @discardableResult
    public static func raise(windowID: Int, bundleID: String) -> Bool {
        let source = """
        tell application id "\(bundleID)"
            set index of (first window whose id is \(windowID)) to 1
            activate
        end tell
        """
        return run(source) != nil
    }

    /// True when the app answers Apple Events at all, so callers can skip apps that never
    /// will and avoid a pointless permission prompt.
    public static func isScriptable(bundleID: String) -> Bool {
        run("tell application id \"\(bundleID)\" to return count of windows") != nil
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 is "not authorised to send Apple events", i.e. the user declined.
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            Log.line("applescript failed (\(code)) for: \(source.prefix(60))")
            return nil
        }
        return result
    }
}
