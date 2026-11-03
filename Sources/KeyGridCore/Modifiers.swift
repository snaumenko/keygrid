/// The modifier keys that can be part of a keyboard shortcut:
/// ⌘ command, ⌃ control, ⌥ option (also called alt), ⇧ shift.
///
/// A value of this type is a set. `[.ctrl, .alt]` means "control and
/// option are held"; `[]` means "no modifier". Swift calls this kind of
/// type an `OptionSet`: it is stored as bits in one small integer, and you
/// use it with set operations such as `contains(.cmd)` or `insert(.shift)`.
///
/// This type only describes which modifiers are held. It knows nothing
/// about which key goes with them; that pairing is the job of `Hotkey`.
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let cmd   = Modifiers(rawValue: 1 << 0)
    public static let ctrl  = Modifiers(rawValue: 1 << 1)
    public static let alt   = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    /// These modifiers as the bit flags that macOS's Carbon hotkey API
    /// (`RegisterEventHotKey`) expects in its second argument,
    /// `inHotKeyModifiers`.
    ///
    /// Carbon uses its own bit positions, defined in Apple's `Events.h`:
    /// cmdKey = 0x0100, shiftKey = 0x0200, optionKey = 0x0800,
    /// controlKey = 0x1000. The numbers are copied here as literals so this
    /// library does not have to import Carbon.
    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.cmd)   { flags |= 0x0100 }
        if contains(.shift) { flags |= 0x0200 }
        if contains(.alt)   { flags |= 0x0800 }
        if contains(.ctrl)  { flags |= 0x1000 }
        return flags
    }

    /// The name printed for each modifier when a shortcut is written as
    /// text, in the order they are printed: `cmd`, `ctrl`, `alt`, `shift`.
    /// Fixing the order means one shortcut always prints the same way.
    static let canonicalOrder: [(Modifiers, String)] = [
        (.cmd, "cmd"), (.ctrl, "ctrl"), (.alt, "alt"), (.shift, "shift"),
    ]

    /// Every spelling a user may type for a modifier in the config file,
    /// and the modifier it means. `alt`, `opt`, and `option` are the same
    /// key.
    static let names: [String: Modifiers] = [
        "cmd": .cmd, "command": .cmd,
        "ctrl": .ctrl, "control": .ctrl,
        "alt": .alt, "opt": .alt, "option": .alt,
        "shift": .shift,
    ]
}
