import Carbon.HIToolbox
import os
import KeyGridCore

/// Registers global keyboard shortcuts with macOS and runs a handler when
/// one is pressed.
///
/// A global shortcut works whichever app is in front. macOS offers two ways
/// to get one. This type uses the older Carbon API, `RegisterEventHotKey`,
/// because it needs no permission from the user and because macOS consumes
/// the keystroke before normal key delivery, so the app in front does not
/// receive it. Apps that watch the keyboard through a `CGEventTap` still
/// see the key; `docs/ARCHITECTURE.md`, "How a hotkey travels", explains
/// that. The alternative, a `CGEventTap`, needs a permission and more code.
///
/// Usage: create one `HotkeyCenter` for the life of the app, call
/// `register(_:handler:)` for each shortcut, and call `unregisterAll()`
/// before registering a new set (for example after the config file
/// changes). Handlers run on the main thread, because the Carbon handler is
/// installed on the application event target and `NSApplication.run()`
/// dispatches those events on the main thread.
///
/// This type knows nothing about what a shortcut does. It only connects a
/// `Hotkey` to a closure.
final class HotkeyCenter {
    enum RegistrationError: Error, CustomStringConvertible {
        /// macOS refused to register the shortcut. `status` is Carbon's
        /// `OSStatus`. `-9878` (`eventHotKeyExistsErr`) means another app
        /// already registered the same combination through Carbon. Apps that
        /// watch keys with a `CGEventTap` do not cause this error; both apps
        /// then receive the key.
        case failed(Hotkey, OSStatus)
        /// Carbon's press handler could not be installed when this
        /// `HotkeyCenter` was created, so no press could ever reach the app.
        /// Nothing is registered in that state, because a registered key
        /// with no handler would be swallowed system-wide for nothing.
        case handlerNotInstalled(OSStatus)

        var description: String {
            switch self {
            case .failed(let hotkey, let status) where status == eventHotKeyExistsErr:
                return "could not register \(hotkey): another app already owns this shortcut (status \(status))"
            case .failed(let hotkey, let status):
                return "could not register \(hotkey): status \(status)"
            case .handlerNotInstalled(let status):
                return "hotkey handler not installed: status \(status); no shortcut can work"
            }
        }
    }

    /// One live registration: the shortcut, Carbon's reference to it (used
    /// to unregister), and the closure to run on a press.
    private struct Registration {
        let hotkey: Hotkey
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    /// Registrations by the integer id handed to Carbon. Carbon reports a
    /// press by id, and this map finds the handler.
    private var registrations: [UInt32: Registration] = [:]
    /// The next id to hand to Carbon. Never reused, even after
    /// `unregisterAll`, so a press queued for an old id cannot hit a new one.
    private var nextID: UInt32 = 1
    /// Carbon's handle for the installed press handler. Removed in `deinit`.
    private var eventHandler: EventHandlerRef?
    /// What `InstallEventHandler` returned when this object was created.
    /// Anything but `noErr` makes every `register` call throw.
    private var installStatus: OSStatus = noErr

    /// Four characters that tag this app's hot key ids inside Carbon. Carbon
    /// passes the tag back on each press; `hotKeyPressed` checks it so it
    /// never runs a handler for an id it did not create. Reads as "YKFL".
    private static let signature: OSType = 0x594B_464C

    /// Errors and oddities go to the unified log under this subsystem. Read
    /// them with `log show --predicate 'subsystem == "com.keygrid.app"'`.
    static let log = Logger(subsystem: "com.keygrid.app", category: "hotkeys")

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Asks macOS to deliver `hotkey` to this app from now on, and stores
    /// `handler` to run on each press. Throws `RegistrationError.failed`
    /// when macOS refuses (see that case for the common cause) and
    /// `RegistrationError.handlerNotInstalled` when presses could never be
    /// delivered.
    func register(_ hotkey: Hotkey, handler: @escaping () -> Void) throws {
        guard installStatus == noErr, eventHandler != nil else {
            throw RegistrationError.handlerNotInstalled(installStatus)
        }

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers.carbonFlags,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            throw RegistrationError.failed(hotkey, status)
        }
        guard let ref else {
            // Carbon reported success but gave back no reference. Treated as
            // an internal error so it never logs as "status 0".
            throw RegistrationError.failed(hotkey, OSStatus(eventInternalErr))
        }
        registrations[id] = Registration(hotkey: hotkey, ref: ref, handler: handler)
    }

    /// Removes every registration. After this, none of the shortcuts reach
    /// this app until `register` is called again. A shortcut Carbon refuses
    /// to release is logged, because the key would stay swallowed with no
    /// handler behind it and a later `register` of the same key would fail.
    func unregisterAll() {
        for (id, registration) in registrations {
            let status = UnregisterEventHotKey(registration.ref)
            if status != noErr {
                Self.log.error("could not unregister \(registration.hotkey, privacy: .public) (id \(id)): status \(status)")
            }
        }
        registrations.removeAll()
    }

    /// Runs the handler for a press reported by Carbon. Called from
    /// `hotKeyPressed` on the main thread. The handler is copied out before
    /// it runs, so a handler that itself calls `register` or
    /// `unregisterAll` does not modify `registrations` while it is being
    /// read.
    private func handlePress(id: UInt32) {
        guard let handler = registrations[id]?.handler else {
            // The id carries this app's signature, so it was minted here.
            // Either the press was queued before `unregisterAll` ran, or
            // bookkeeping is wrong. Worth a trace either way.
            Self.log.error("hot key press for id \(id), which has no registration")
            return
        }
        handler()
    }

    /// Tells Carbon to call `hotKeyPressed` for every "hot key pressed"
    /// event aimed at this app. Installed once, in `init`. The result is
    /// kept in `installStatus`; on failure `register` refuses to register
    /// anything, since no press could ever be delivered.
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Carbon calls a plain C function, which cannot capture `self`.
        // `self` travels through the userData pointer instead. The pointer
        // is unretained, so it is valid only while this object lives;
        // `deinit` removes the handler before the object goes away.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyPressed,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        if installStatus != noErr {
            Self.log.error("InstallEventHandler failed: status \(self.installStatus)")
        }
    }

    /// The C-compatible callback Carbon invokes. It reads the hot key id out
    /// of the event, drops anything not tagged with `signature`, recovers the
    /// `HotkeyCenter` from `userData`, and forwards to `handlePress(id:)`.
    /// Returning `eventNotHandledErr` lets Carbon offer the event to other
    /// handlers; `noErr` says it is consumed.
    private let hotKeyPressed: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            HotkeyCenter.log.error("hot key callback called with a nil event or userData")
            return OSStatus(eventNotHandledErr)
        }

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
        guard status == noErr else {
            HotkeyCenter.log.error("could not read the hot key id from a press event: status \(status)")
            return status
        }
        guard hotKeyID.signature == HotkeyCenter.signature else {
            return OSStatus(eventNotHandledErr)   // not ours; let the next handler see it
        }

        let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
        center.handlePress(id: hotKeyID.id)
        return noErr
    }
}
