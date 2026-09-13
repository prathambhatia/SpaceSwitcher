import Foundation

/// Minimal stderr logging. Visible when the binary is run from a terminal, and captured by
/// the system log when launched normally — enough to diagnose hotkey registration and
/// switch outcomes without attaching a debugger.
public enum Log {
    public static func line(_ message: String) {
        FileHandle.standardError.write("[SpaceSwitcher] \(message)\n".data(using: .utf8)!)
    }
}
