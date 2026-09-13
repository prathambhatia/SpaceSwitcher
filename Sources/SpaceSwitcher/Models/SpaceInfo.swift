import AppKit
import CoreGraphics
import Foundation

/// One tile in the Mission Control strip: either a Desktop or a fullscreen/tiled app Space.
public struct SpaceInfo: Identifiable {

    public enum Kind {
        /// A regular Desktop. `ordinal` is its 1-based position *among Desktops only*,
        /// which is what macOS's "Switch to Desktop N" shortcut counts.
        case desktop(ordinal: Int)
        /// A fullscreen or Split View Space. Split View holds two apps, hence an array.
        case fullscreen(pids: [pid_t])
    }

    /// macOS `ManagedSpaceID`.
    public let id: Int
    /// 1-based position in the Mission Control strip — what ⌘N maps to.
    public let position: Int
    public let kind: Kind
    /// Window IDs of the fullscreen windows occupying this Space, if any.
    public let fullscreenWindowIDs: [CGWindowID]

    public init(id: Int, position: Int, kind: Kind, fullscreenWindowIDs: [CGWindowID]) {
        self.id = id
        self.position = position
        self.kind = kind
        self.fullscreenWindowIDs = fullscreenWindowIDs
    }

    public var isDesktop: Bool {
        if case .desktop = kind { return true }
        return false
    }

    /// Apps occupying this Space, for display and for activation-based switching.
    public var applications: [NSRunningApplication] {
        guard case .fullscreen(let pids) = kind else { return [] }
        return pids.compactMap { NSRunningApplication(processIdentifier: $0) }
    }

    /// Menu label, e.g. `Desktop 2` or `Slack`.
    public var label: String {
        switch kind {
        case .desktop(let ordinal):
            return "Desktop \(ordinal)"
        case .fullscreen:
            let names = applications.compactMap(\.localizedName)
            if names.isEmpty { return "Fullscreen app" }
            // Split View shows both, e.g. "Safari + Notes".
            return names.joined(separator: " + ")
        }
    }
}
