/// What the status menu's "Launch at Login" item shows for each state
/// macOS reports about KeyGrid's login item.
///
/// The login item itself is macOS's: `SMAppService` in the app registers
/// and unregisters it and reports its status, and System Settings →
/// General → Login Items & Extensions lists it. This type only turns one
/// of four states into the item's title, checkmark and enabled flag, so
/// the wording is in one tested place and `StatusMenu` decides nothing.
/// `AppController` maps `SMAppService.Status` onto these cases; "How
/// launch at login works" in `docs/ARCHITECTURE.md` tells the whole path.
public enum LoginItemState: Equatable, Sendable {
    /// No login item: KeyGrid does not open at login. A click registers.
    case off
    /// Registered and allowed: KeyGrid opens at login. A click
    /// unregisters.
    case on
    /// Registered, but macOS wants the person to allow it in System
    /// Settings before it takes effect. A click opens that pane.
    case needsApproval
    /// macOS reports a status this version of KeyGrid does not know
    /// (a value a later macOS adds to `SMAppService.Status`).
    /// The item is shown disabled so the state is visible, not hidden.
    case unavailable

    /// The menu item's title. Every state's title starts with "Launch at
    /// Login", so the eye finds the item in one place in the menu; the two
    /// states that need a word get it after a colon.
    public var menuTitle: String {
        switch self {
        case .off, .on:      return "Launch at Login"
        case .needsApproval: return "Launch at Login: approve in System Settings…"
        case .unavailable:   return "Launch at Login: unavailable"
        }
    }

    /// Whether the item carries a checkmark: only when the login item is
    /// registered and allowed, so a checkmark means "it will open".
    public var isChecked: Bool { self == .on }

    /// Whether the item can be clicked. Only `unavailable` is disabled:
    /// there is nothing a click could do about a bundle macOS cannot find.
    public var isEnabled: Bool { self != .unavailable }
}
