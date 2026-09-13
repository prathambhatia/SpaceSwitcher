import AppKit
import CoreGraphics
import Foundation

/// Reads the Mission Control strip — the ordered list of Spaces on the active display.
///
/// Two sources are combined:
///
/// * **Order** comes from `PrivateSpaceAPI` (see that file for the trade-off), because no
///   public API reports it correctly. If the private symbol is unavailable the
///   `com.apple.spaces` preference order is used instead, which keeps the app working but
///   can mis-order fullscreen Spaces.
/// * **Details** — which app owns a fullscreen Space, and its window id — come from the
///   `com.apple.spaces` preference domain, read through ordinary CFPreferences.
///
/// Known limitation: that domain's `Current Space` entry is written lazily and is often
/// stale right after a switch, so it is never used. Current Space is derived from live
/// window state instead.
public final class SpaceManager {

    private static let domain = "com.apple.spaces" as CFString
    private static let configurationKey = "SpacesDisplayConfiguration" as CFString

    private enum SpaceType {
        static let desktop = 0
    }

    /// Per-Space details from the preference file, keyed by ManagedSpaceID.
    private struct SpaceDetails {
        let type: Int
        let pids: [pid_t]
        let windowIDs: [CGWindowID]
    }

    public init() {}

    /// True when Space ordering is coming from the authoritative source.
    public var hasAccurateOrdering: Bool { PrivateSpaceAPI.isAvailable }

    /// Spaces on the active display, in Mission Control strip order (left to right).
    ///
    /// Ghost Spaces are dropped: the Dock leaves an entry behind when a fullscreen window
    /// closes, and counting those would shift every ⌘N after it onto the wrong Space.
    public func spaces() -> [SpaceInfo] {
        let details = spaceDetails()
        let order = orderedSpaceIDs(fallback: Array(details.fallbackOrder))
        let liveWindows = allWindowIDs()

        var result: [SpaceInfo] = []
        var desktopOrdinal = 0

        for spaceID in order {
            guard let detail = details.byID[spaceID] else { continue }

            let kind: SpaceInfo.Kind
            if detail.type == SpaceType.desktop {
                desktopOrdinal += 1
                kind = .desktop(ordinal: desktopOrdinal)
            } else {
                // A fullscreen Space whose window no longer exists is a leftover entry.
                guard detail.windowIDs.contains(where: liveWindows.contains) else { continue }
                // A Split View partner that has quit leaves a dead pid behind.
                let livePIDs = detail.pids.filter { NSRunningApplication(processIdentifier: $0) != nil }
                guard !livePIDs.isEmpty else { continue }
                kind = .fullscreen(pids: livePIDs)
            }

            result.append(
                SpaceInfo(
                    id: spaceID,
                    position: result.count + 1,
                    kind: kind,
                    fullscreenWindowIDs: detail.windowIDs
                )
            )
        }
        return result
    }

    /// Whether `space` is the one on screen.
    public func isCurrent(_ space: SpaceInfo) -> Bool {
        currentSpaceID() == space.id
    }

    /// The Space on screen, or nil if it cannot be identified.
    public func currentSpace(in spaces: [SpaceInfo]) -> SpaceInfo? {
        guard let id = currentSpaceID() else { return nil }
        return spaces.first { $0.id == id }
    }

    /// Live current Space id. Falls back to matching on-screen windows against recorded
    /// fullscreen window ids, which is weaker: it cannot identify a Desktop, and a Space's
    /// recorded `fs_wid` goes stale when its window is replaced.
    private func currentSpaceID() -> Int? {
        if let id = PrivateSpaceAPI.currentSpaceID() { return id }

        let visible = visibleWindowIDs()
        guard !visible.isEmpty else { return nil }
        let details = spaceDetails()
        return details.byID.first { _, detail in
            !detail.windowIDs.isEmpty && detail.windowIDs.contains(where: visible.contains)
        }?.key
    }

    // MARK: - Ordering

    private func orderedSpaceIDs(fallback: [Int]) -> [Int] {
        guard let ordered = PrivateSpaceAPI.orderedSpaces() else { return fallback }
        let ids = ordered.map(\.id)
        // Guard against a partial read leaving Spaces unreachable by ⌘N.
        return Set(ids) == Set(fallback) ? ids : fallback
    }

    // MARK: - Preference file

    private func spaceDetails() -> (byID: [Int: SpaceDetails], fallbackOrder: [Int]) {
        guard let monitor = activeMonitor(),
              let rawSpaces = monitor["Spaces"] as? [[String: Any]]
        else { return ([:], []) }

        var byID: [Int: SpaceDetails] = [:]
        var order: [Int] = []

        for raw in rawSpaces {
            guard let id = raw["ManagedSpaceID"] as? Int else { continue }
            order.append(id)
            byID[id] = SpaceDetails(
                type: raw["type"] as? Int ?? SpaceType.desktop,
                pids: integers(from: raw["pid"]).map { pid_t($0) },
                windowIDs: integers(from: raw["fs_wid"]).map { CGWindowID($0) }
            )
        }
        return (byID, order)
    }

    private func activeMonitor() -> [String: Any]? {
        // Force a re-read; the Dock updates this domain behind our back.
        CFPreferencesAppSynchronize(Self.domain)
        guard let configuration = CFPreferencesCopyAppValue(Self.configurationKey, Self.domain) as? [String: Any],
              let management = configuration["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]]
        else { return nil }

        return monitors.first { ($0["Display Identifier"] as? String) == "Main" } ?? monitors.first
    }

    /// The `pid` and `fs_wid` keys hold a scalar for a fullscreen app and an array for a
    /// Split View pair, so both shapes have to be accepted.
    private func integers(from value: Any?) -> [Int] {
        if let single = value as? Int { return [single] }
        if let many = value as? [Int] { return many }
        return []
    }

    // MARK: - Window state

    /// Window IDs on the current Space. `.optionOnScreenOnly` restricts this to the active
    /// Space and needs no Screen Recording permission because only IDs are read.
    private func visibleWindowIDs() -> Set<CGWindowID> {
        windowIDs(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    /// Every window the server knows about, including those on other Spaces.
    private func allWindowIDs() -> Set<CGWindowID> {
        windowIDs(options: [.optionAll])
    }

    private func windowIDs(options: CGWindowListOption) -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return Set(raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    public func observeSpaceChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in handler() }
    }
}
