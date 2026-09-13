import AppKit
import CoreGraphics
import Foundation

/// Switches to a Space by its Mission Control strip position.
///
/// Every mechanism here is public API. Three are needed because no single one reaches
/// every kind of Space:
///
/// 1. **Fullscreen Space, sole one owned by its app** — activate the app. Instant, and the
///    common case.
/// 2. **Desktop** — synthesise macOS's own ⌃N "Switch to Desktop N" shortcut. Nothing to
///    activate, and no public API moves to a Desktop directly.
/// 3. **Fullscreen Space whose app owns more than one** — activation is ambiguous (it
///    lands on whichever window was last focused) and Accessibility cannot disambiguate
///    either, because `kAXWindowsAttribute` omits all but one fullscreen window of an app.
///    So: jump to the nearest Desktop with ⌃N, which puts us at a *known* strip position,
///    then step with ⌃←/⌃→ the exact remaining distance.
///
/// Case 3 is the slow path — it animates through intermediate Spaces — but it is the only
/// public way to reach a specific one of several fullscreen Spaces owned by one app
/// (two Chrome windows in fullscreen, for example).
public final class SpaceSwitcher {

    public enum Outcome {
        case switched(SpaceInfo)
        case navigating(SpaceInfo, steps: Int)
        case noSuchSpace(position: Int, available: Int)
        case desktopShortcutUnavailable(SpaceInfo, desktopOrdinal: Int)
        case unreachable(SpaceInfo)
        case accessibilityRequired
    }

    /// Virtual key codes for digits 1–9. Deliberately not contiguous.
    private static let digitKeyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let leftArrow: CGKeyCode = 123
    private static let rightArrow: CGKeyCode = 124

    /// Steps are paced by `activeSpaceDidChangeNotification`, not by these values; they
    /// are only the ceiling for how long to wait before assuming a keystroke was dropped.
    private static let stepDelay: TimeInterval = 0.1
    private static let anchorSettle: TimeInterval = 0.1
    private static let changeTimeout: TimeInterval = 1.4
    /// How long a synthesised key is held before its release is posted.
    private static let keyHoldDuration: TimeInterval = 0.05
    /// The notification can arrive just before the window server settles.
    private static let settleAfterChange: TimeInterval = 0.25
    /// How long to give activation before deciding it failed and stepping instead.
    private static let activationGrace: TimeInterval = 0.8

    private let spaceManager: SpaceManager
    private let accessibility: AccessibilityManager
    private let memory: SpaceWindowMemory

    /// Invalidates an in-flight step sequence when a new request arrives, so two
    /// navigations cannot fight over the keyboard.
    private var navigationToken = 0
    /// Held for the duration of a step sequence to keep App Nap from throttling it.
    private var activity: NSObjectProtocol?

    public init(
        spaceManager: SpaceManager,
        accessibility: AccessibilityManager,
        memory: SpaceWindowMemory = SpaceWindowMemory()
    ) {
        self.spaceManager = spaceManager
        self.accessibility = accessibility
        self.memory = memory
    }

    @discardableResult
    public func switchTo(position: Int) -> Outcome {
        // Re-read every time: the strip changes as fullscreen apps come and go.
        let spaces = spaceManager.spaces()
        guard position >= 1, position <= spaces.count else {
            return .noSuchSpace(position: position, available: spaces.count)
        }
        return switchTo(spaces[position - 1], in: spaces)
    }

    @discardableResult
    public func switchTo(_ space: SpaceInfo) -> Outcome {
        switchTo(space, in: spaceManager.spaces())
    }

    @discardableResult
    public func switchTo(_ space: SpaceInfo, in spaces: [SpaceInfo]) -> Outcome {
        switch space.kind {
        case .desktop(let ordinal):
            return switchToDesktop(space, in: spaces, ordinal: ordinal)

        case .fullscreen:
            // An app owning several fullscreen Spaces cannot be reached by activation, but
            // raising the exact window that lives there can — if we have learned which one.
            if !ownsSingleSpace(space, in: spaces), raiseRememberedWindow(for: space) {
                return .switched(space)
            }

            if ownsSingleSpace(space, in: spaces), let app = space.applications.first {
                app.activate()
                // Activation silently does nothing when the app has no live window — a
                // Split View partner that quit leaves its Space in exactly that state —
                // so confirm we arrived and fall back to stepping if we did not.
                let token = beginNavigation()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationGrace) { [weak self] in
                    guard let self, self.navigationToken == token else { return }
                    guard !self.spaceManager.isCurrent(space) else { return }
                    self.step(towardsSpace: space.id, budget: spaces.count + 2, token: token)
                }
                return .switched(space)
            }
            return navigate(to: space, in: spaces)
        }
    }

    // MARK: - Desktops

    /// macOS's own ⌃N jumps to a Desktop instantly, but that shortcut is off by default and
    /// a newly created Desktop arrives with it off, so it is treated as an optimisation
    /// rather than a requirement: without it, the Desktop is reached by stepping, which
    /// needs no setup at all.
    private func switchToDesktop(_ space: SpaceInfo, in spaces: [SpaceInfo], ordinal: Int) -> Outcome {
        guard accessibility.isTrusted else { return .accessibilityRequired }

        if ordinal >= 1,
           ordinal <= Self.digitKeyCodes.count,
           MissionControlShortcuts.isDesktopShortcutEnabled(ordinal: ordinal) {
            post(keyCode: Self.digitKeyCodes[ordinal - 1], flags: .maskControl)
            return .switched(space)
        }
        return navigate(to: space, in: spaces)
    }

    // MARK: - Fullscreen

    /// Jumps straight to `space` by raising the window previously learned to live there.
    ///
    /// Returns false when nothing has been learned yet, the app is not scriptable, or the
    /// window has since gone — the caller then steps there and learns on arrival.
    private func raiseRememberedWindow(for space: SpaceInfo) -> Bool {
        guard let remembered = memory.lookup(spaceID: space.id) else { return false }
        guard ScriptableWindows.raise(windowID: remembered.windowID, bundleID: remembered.bundleID) else {
            memory.forget(spaceID: space.id)
            return false
        }

        // Raising reports success even if it left us elsewhere, so confirm and re-learn.
        let token = beginNavigation()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationGrace) { [weak self] in
            guard let self, self.navigationToken == token else { return }
            if self.spaceManager.isCurrent(space) {
                self.endNavigation()
            } else {
                self.memory.forget(spaceID: space.id)
                self.step(towardsSpace: space.id, budget: 12, token: token)
            }
        }
        return true
    }

    /// Records which window occupies a Space, once we are standing on it.
    private func learnWindow(for space: SpaceInfo) {
        guard case .fullscreen = space.kind,
              let bundleID = space.applications.first?.bundleIdentifier,
              let windowID = ScriptableWindows.frontWindowID(bundleID: bundleID)
        else { return }
        memory.record(spaceID: space.id, bundleID: bundleID, windowID: windowID)
    }

    /// True when no other Space is owned by the same application, making activation
    /// unambiguous.
    private func ownsSingleSpace(_ space: SpaceInfo, in spaces: [SpaceInfo]) -> Bool {
        guard case .fullscreen(let pids) = space.kind else { return false }
        let owners = Set(pids)
        let sharing = spaces.filter { other in
            guard other.id != space.id, case .fullscreen(let otherPIDs) = other.kind else { return false }
            return !owners.isDisjoint(with: Set(otherPIDs))
        }
        return sharing.isEmpty
    }

    /// Steps to `target` with ⌃←/⌃→, the only public mechanism that reaches an arbitrary
    /// Space.
    private func navigate(to target: SpaceInfo, in spaces: [SpaceInfo]) -> Outcome {
        guard accessibility.isTrusted else { return .accessibilityRequired }

        let current = spaceManager.currentSpace(in: spaces)
        guard current != nil || nearestAnchor(to: target, in: spaces) != nil else {
            // Position unknown and no Desktop to anchor on; activation is all that is left.
            if let app = target.applications.first {
                app.activate()
                return .switched(target)
            }
            return .unreachable(target)
        }

        let steps = current.map { abs(target.position - $0.position) } ?? 0
        let token = beginNavigation()
        // Scheduled rather than called inline: the first keystroke must be posted from a
        // running run loop, otherwise the window server ignores it.
        schedule(towardsSpace: target.id, budget: spaces.count + 2, token: token, after: 0.05)
        return .navigating(target, steps: steps)
    }

    private func beginNavigation() -> Int {
        navigationToken += 1
        // Without this the step chain stalls after the first keystroke: this is a
        // background accessory app with no visible UI, so App Nap throttles its scheduled
        // work as soon as the Space switches away from it.
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Switching Spaces"
            )
        }
        return navigationToken
    }

    private func endNavigation() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    /// Closest Desktop whose ⌃N shortcut is actually enabled — a known strip position to
    /// step from.
    private func nearestAnchor(to target: SpaceInfo, in spaces: [SpaceInfo]) -> (position: Int, ordinal: Int)? {
        spaces
            .compactMap { space -> (position: Int, ordinal: Int)? in
                guard case .desktop(let ordinal) = space.kind,
                      MissionControlShortcuts.isDesktopShortcutEnabled(ordinal: ordinal)
                else { return nil }
                return (space.position, ordinal)
            }
            .min { abs($0.position - target.position) < abs($1.position - target.position) }
    }

    /// Moves one Space toward `target`, then reschedules itself.
    ///
    /// Position is re-read before every step, so a keystroke the window server drops
    /// simply costs an extra step instead of landing on the wrong Space.
    ///
    /// Runs on the main thread deliberately: a synthesised ⌃← / ⌃→ posted from a
    /// background thread is accepted by `CGEvent.post` and then silently ignored by the
    /// window server. Hence the scheduled-block chain rather than sleeping on a worker.
    private func step(towardsSpace targetID: Int, budget: Int, token: Int) {
        guard navigationToken == token else { return }
        guard budget > 0 else { endNavigation(); return }

        // Re-read the strip every step and find the target by id, never by the position it
        // held when navigation began. Creating a Desktop or closing a fullscreen window
        // mid-flight renumbers everything after it, and a stale position would land on
        // the wrong Space.
        let spaces = spaceManager.spaces()
        guard let target = spaces.first(where: { $0.id == targetID }) else {
            // The Space was closed while we were on our way to it.
            endNavigation()
            return
        }
        guard !spaceManager.isCurrent(target) else {
            // Arrived by stepping — record the window here so next time is instant.
            learnWindow(for: target)
            endNavigation()
            return
        }

        guard let current = spaceManager.currentSpace(in: spaces) else {
            // Position unknown: jump to a Desktop, which puts us somewhere known.
            guard let anchor = nearestAnchor(to: target, in: spaces) else { endNavigation(); return }
            post(keyCode: Self.digitKeyCodes[anchor.ordinal - 1], flags: .maskControl)
            schedule(towardsSpace: targetID, budget: budget - 1, token: token, after: Self.anchorSettle)
            return
        }

        let delta = target.position - current.position
        Log.line("step: at \(current.position), want \(target.position), delta \(delta), budget \(budget)")
        guard delta != 0 else { endNavigation(); return }

        // Every ⌃← / ⌃→ costs an animation and can be dropped, so if a Desktop sits closer
        // to the target than we currently are, jump straight there with ⌃N and step from
        // there instead. Reaching position 7 from position 1 is six steps; from Desktop 3
        // at position 5 it is two.
        if let anchor = nearestAnchor(to: target, in: spaces),
           abs(target.position - anchor.position) < abs(delta) - 1 {
            Log.line("step: anchoring on Desktop \(anchor.ordinal) at position \(anchor.position)")
            post(keyCode: Self.digitKeyCodes[anchor.ordinal - 1], flags: .maskControl)
            schedule(towardsSpace: targetID, budget: budget - 1, token: token, after: Self.anchorSettle)
            return
        }

        postArrow(keyCode: delta > 0 ? Self.rightArrow : Self.leftArrow)
        schedule(towardsSpace: targetID, budget: budget - 1, token: token, after: Self.stepDelay)
    }

    /// Waits for the Space switch to actually complete before taking the next step.
    ///
    /// A fixed delay cannot work here: too short and the next keystroke is swallowed or,
    /// worse, position is re-read before the switch lands and the chain overshoots; too
    /// long and every switch feels sluggish. macOS reports completion directly, so wait
    /// for that, with a timeout so a swallowed keystroke cannot hang the sequence.
    private func schedule(
        towardsSpace targetID: Int,
        budget: Int,
        token: Int,
        after delay: TimeInterval
    ) {
        var resumed = false
        var observer: NSObjectProtocol?

        let resume: () -> Void = { [weak self] in
            guard !resumed else { return }
            resumed = true
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            // The notification can land marginally before the window server's own state
            // catches up, so let it settle before reading position.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleAfterChange) {
                self?.step(towardsSpace: targetID, budget: budget, token: token)
            }
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in resume() }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.changeTimeout) { resume() }
    }

    // MARK: - Event synthesis

    /// Synthesises a modified keypress at the HID tap so macOS handles it exactly as if
    /// typed. Requires Accessibility authorisation.
    ///
    /// The source is `.privateState`, not `.hidSystemState`, because the latter merges in
    /// whatever modifiers are physically held. These shortcuts fire from ⌘N, so with the
    /// shared state a synthesised ⌃→ arrives as ⌘⌃→ and matches no Space shortcut at all —
    /// posted successfully, silently ignored.
    /// Posts ⌃← / ⌃→.
    ///
    /// Arrow keys must carry `.maskNumericPad`: real arrow events from a keyboard include
    /// it, and macOS's "Move left/right a space" shortcut will not match without it. This
    /// is why a synthesised ⌃N reaches a Desktop but a synthesised ⌃→ was posted
    /// successfully and then silently ignored.
    private func postArrow(keyCode: CGKeyCode) {
        post(keyCode: keyCode, flags: [.maskControl, .maskNumericPad, .maskSecondaryFn])
    }

    private func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        // Real keypresses hold for tens of milliseconds. Posting the release in the same
        // instant makes the system shortcut matcher miss the chord most of the time.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyHoldDuration) {
            up.post(tap: .cghidEventTap)
        }
    }
}

/// Reads which of macOS's "Switch to Desktop N" shortcuts are currently enabled.
///
/// These live in `com.apple.symbolichotkeys` as ids 118 upward. They cannot be reliably
/// enabled programmatically on modern macOS — writes land on disk but the Dock ignores
/// them — so the app reads their state and asks the user to tick the box instead.
public enum MissionControlShortcuts {

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    public static func symbolicHotkeyID(desktopOrdinal: Int) -> Int { 117 + desktopOrdinal }

    public static func isDesktopShortcutEnabled(ordinal: Int) -> Bool {
        CFPreferencesAppSynchronize(domain)
        guard let all = CFPreferencesCopyAppValue(key, domain) as? [String: Any],
              let entry = all[String(symbolicHotkeyID(desktopOrdinal: ordinal))] as? [String: Any]
        else { return false }
        return (entry["enabled"] as? Bool) ?? false
    }

    /// Desktop ordinals that exist but have no usable shortcut, so the user can be told
    /// exactly which boxes to tick.
    public static func desktopsMissingShortcuts(in spaces: [SpaceInfo]) -> [Int] {
        spaces.compactMap { space in
            guard case .desktop(let ordinal) = space.kind else { return nil }
            return isDesktopShortcutEnabled(ordinal: ordinal) ? nil : ordinal
        }
    }
}
