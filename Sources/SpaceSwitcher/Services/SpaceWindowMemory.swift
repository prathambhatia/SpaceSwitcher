import Foundation

/// Remembers which application window sits on which Space.
///
/// There is no way to ask macOS "which window is on Space N" — so the mapping is learned
/// instead: the first time a Space is reached by stepping, the window that ends up in
/// front is recorded against it. Later requests raise that window directly and arrive
/// instantly.
///
/// Entries are a cache, never a source of truth. A window that has been closed, moved to
/// another Space, or whose app has quit simply fails to raise, and the caller falls back
/// to stepping and re-learns.
public final class SpaceWindowMemory {

    private struct Entry: Codable {
        let bundleID: String
        let windowID: Int
    }

    private static let defaultsKey = "SpaceWindowMemory"

    private var entries: [String: Entry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
                  let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    public init() {}

    public func lookup(spaceID: Int) -> (bundleID: String, windowID: Int)? {
        guard let entry = entries[String(spaceID)] else { return nil }
        return (entry.bundleID, entry.windowID)
    }

    public func record(spaceID: Int, bundleID: String, windowID: Int) {
        var current = entries
        guard current[String(spaceID)]?.windowID != windowID else { return }
        current[String(spaceID)] = Entry(bundleID: bundleID, windowID: windowID)
        entries = current
        Log.line("learned: space \(spaceID) -> \(bundleID) window \(windowID)")
    }

    public func forget(spaceID: Int) {
        var current = entries
        guard current.removeValue(forKey: String(spaceID)) != nil else { return }
        entries = current
    }
}
