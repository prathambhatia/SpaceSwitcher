import Carbon.HIToolbox
import Foundation

/// Registers the ⌘1 … ⌘9 global shortcuts for switching Spaces.
///
/// Uses `RegisterEventHotKey`, which is event-driven (no polling), requires no TCC
/// permission of its own, and never sees keystrokes other than the chords registered.
/// The alternatives are worse here: a `CGEventTap` would route *every* keystroke on the
/// system through this process and demands Accessibility/Input Monitoring, and
/// `NSEvent.addGlobalMonitorForEvents` has the same privacy cost. Carbon's Hot Key
/// Manager is soft-deprecated but remains the only API macOS offers for registering a
/// specific system-wide chord, and is what shipping utilities still use.
public final class HotkeyManager {

    /// Digits 1–9. Note these key codes are not contiguous — 5/6 and 7/8/9 are out of order.
    private static let digitKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]

    private static let signature: OSType = 0x576E_5377  // 'WnSw'

    /// Carbon modifier mask. Plain ⌘ by default, matching the configured shortcut.
    ///
    /// Note ⌘1–9 is claimed by many apps (browser tabs, Slack workspaces, Finder view
    /// modes); a global registration wins over those everywhere, which is why this is
    /// settable rather than hard-coded.
    public var modifiers: UInt32 = UInt32(cmdKey)

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    /// Invoked with the 1-based Space position for the pressed chord.
    public var onShortcut: ((Int) -> Void)?

    public init() {}

    deinit { unregisterAll() }

    public var isRegistered: Bool { handlerRef != nil }

    /// Installs the handler and registers all nine chords. Returns the count registered.
    @discardableResult
    public func registerAll() -> Int {
        guard handlerRef == nil else { return hotKeyRefs.count }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return 0 }

        var registered = 0

        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
            // A conflicting registration by another app fails only that chord.
            if result == noErr, ref != nil {
                hotKeyRefs.append(ref)
                registered += 1
            }
        }
        return registered
    }

    public func unregisterAll() {
        for ref in hotKeyRefs where ref != nil {
            UnregisterEventHotKey(ref!)
        }
        hotKeyRefs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func handle(position: Int) {
        onShortcut?(position)
    }
}

/// C callback — must not capture, so the instance arrives via `userData`.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handle(position: Int(hotKeyID.id))
    return noErr
}
