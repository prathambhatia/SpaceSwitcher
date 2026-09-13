import CoreGraphics
import Foundation

/// Read-only access to the window server's ordered Space list.
///
/// Why this exists: no public API reports the Mission Control strip order. The
/// `com.apple.spaces` preference domain was tried first and is provably wrong — captured
/// simultaneously with Mission Control it reported
/// `Desktop, Chrome, Desktop, Slack, …` where the strip showed
/// `Desktop 1, Desktop 2, Slack, Chrome, …`. `Space Properties` is sorted by space id, and
/// ⌃→ traversal races the switch animation. Without the true order, ⌘N points at the wrong
/// Space, which is the whole feature.
///
/// The trade-off, stated plainly: `CGSCopyManagedDisplaySpaces` is undocumented and Apple
/// can remove or change it in any macOS release. Three things bound that risk:
///
/// 1. It is resolved with `dlsym` at runtime, never linked. A missing symbol degrades to
///    the preference-file order rather than failing to launch.
/// 2. It is used **only to read ordering**. Every state change — activating an app,
///    sending ⌃N — goes through public API, so nothing private ever mutates the system.
/// 3. The returned data is validated before use; anything unexpected falls back.
///
/// Revisit if Apple ships a public Spaces API, or if this stops returning data after an
/// OS update — the fallback keeps the app working, but ⌘N ordering will be wrong until
/// the ordering source is replaced.
enum PrivateSpaceAPI {

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// One Space as the window server orders it.
    struct RawSpace {
        let id: Int
        let type: Int
        let uuid: String
    }

    private static let symbols: (connection: MainConnectionID, copySpaces: CopyManagedDisplaySpaces)? = {
        // The symbols live in SkyLight; the global handle usually resolves them because
        // AppKit has already loaded it, but open it explicitly as a fallback.
        var handle = dlopen(nil, RTLD_NOW)
        var connection = dlsym(handle, "CGSMainConnectionID")
        var copySpaces = dlsym(handle, "CGSCopyManagedDisplaySpaces")

        if connection == nil || copySpaces == nil {
            handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
            connection = dlsym(handle, "CGSMainConnectionID")
            copySpaces = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        }

        guard let connection, let copySpaces else { return nil }
        return (
            unsafeBitCast(connection, to: MainConnectionID.self),
            unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self)
        )
    }()

    static var isAvailable: Bool { symbols != nil }

    /// Spaces on the given display in true Mission Control order, or nil if unavailable.
    static func orderedSpaces(displayIdentifier: String = "Main") -> [RawSpace]? {
        snapshot(displayIdentifier: displayIdentifier)?.spaces
    }

    /// The Space currently on screen. Unlike the `com.apple.spaces` preference — which is
    /// written lazily and is routinely stale straight after a switch — this is live, and
    /// it identifies Desktops too, which window state alone cannot.
    static func currentSpaceID(displayIdentifier: String = "Main") -> Int? {
        snapshot(displayIdentifier: displayIdentifier)?.currentID
    }

    private static func snapshot(displayIdentifier: String) -> (spaces: [RawSpace], currentID: Int?)? {
        guard let symbols else { return nil }
        guard let displays = symbols.copySpaces(symbols.connection())?.takeRetainedValue() as? [[String: Any]],
              !displays.isEmpty
        else { return nil }

        let display = displays.first { ($0["Display Identifier"] as? String) == displayIdentifier }
            ?? displays[0]

        guard let raw = display["Spaces"] as? [[String: Any]] else { return nil }

        let spaces = raw.compactMap(rawSpace)
        // An empty or partial result means the shape changed; prefer the fallback.
        guard spaces.count == raw.count, !spaces.isEmpty else { return nil }

        let current = (display["Current Space"] as? [String: Any]).flatMap(rawSpace)
        return (spaces, current?.id)
    }

    private static func rawSpace(_ entry: [String: Any]) -> RawSpace? {
        guard let id = entry["ManagedSpaceID"] as? Int ?? entry["id64"] as? Int else { return nil }
        return RawSpace(
            id: id,
            type: entry["type"] as? Int ?? 0,
            uuid: entry["uuid"] as? String ?? ""
        )
    }
}
