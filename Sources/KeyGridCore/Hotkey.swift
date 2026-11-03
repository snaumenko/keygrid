/// One keyboard shortcut, for example ⌃⌥⇧← or ⌃⌥[.
///
/// A shortcut is a set of modifier keys (`modifiers`) plus exactly one
/// other key (`keyCode`). The key is stored as a *virtual key code*: a
/// number that names a physical key position, as defined by Apple's
/// `kVK_*` constants in `Events.h`. `0x7B` is the left-arrow key, `0x12`
/// is the key labelled 1 on a US keyboard. macOS's global hotkey API takes
/// exactly this number, so no translation is needed when a shortcut is
/// registered.
///
/// Shortcuts enter the program as text from the user's config file, such
/// as `"ctrl+alt+left"`. `Hotkey.parse(_:)` reads that text format, and
/// `description` writes it. The format is:
///
///   - parts separated by `+`
///   - any number of modifier names, including none: `cmd` or `command`,
///     `ctrl` or `control`, `alt` or `opt` or `option`, `shift`
///   - exactly one key name from the `KeyNames` table
///   - case and spaces around `+` do not matter
///
/// Anything that needs a full shortcut from text must call `parse(_:)`.
/// The one other reader of this format is `Config.parseModifiers`, which
/// accepts the modifier part alone (`"ctrl+alt"`) for the Dock section,
/// whose key is always a digit. `docs/ARCHITECTURE.md` describes how a
/// parsed hotkey is then used.
public struct Hotkey: Hashable, Sendable, CustomStringConvertible {
    public let modifiers: Modifiers
    public let keyCode: UInt32

    public init(modifiers: Modifiers, keyCode: UInt32) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// Reads a shortcut from its text form, for example `"ctrl+alt+left"`.
    /// Throws a `HotkeyParseError` when the text does not follow the format
    /// described on `Hotkey`. The `unknownKey` case carries the word that
    /// was not recognised; the other cases are identified by the case alone.
    public static func parse(_ text: String) throws -> Hotkey {
        let parts = text
            .lowercased()
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingWhitespace() }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw HotkeyParseError.empty }

        var modifiers = Modifiers()
        var keyCode: UInt32?
        for part in parts {
            if let modifier = Modifiers.names[part] {
                modifiers.insert(modifier)
            } else if let code = KeyNames.keyCode(for: part) {
                guard keyCode == nil else { throw HotkeyParseError.multipleKeys }
                keyCode = code
            } else {
                throw HotkeyParseError.unknownKey(part)
            }
        }
        guard let keyCode else { throw HotkeyParseError.missingKey }
        return Hotkey(modifiers: modifiers, keyCode: keyCode)
    }

    /// Writes the shortcut in its text form, always spelled the same way:
    /// modifiers in the order `cmd`, `ctrl`, `alt`, `shift`, then the key
    /// name, joined with `+`. Example: `"ctrl+alt+left"`.
    ///
    /// For a key code that is in the `KeyNames` table, feeding this string
    /// back to `parse(_:)` gives an equal `Hotkey`. A code that is not in the
    /// table (possible because `init` accepts any number) prints as hex, for
    /// example `"0xff"`. `parse(_:)` does not accept that form; it exists
    /// only so the value is still readable in an error message.
    public var description: String {
        var parts = Modifiers.canonicalOrder
            .filter { modifiers.contains($0.0) }
            .map { $0.1 }
        // A code outside the KeyNames table has no name. Print it as hex so it
        // is at least readable in an error message. parse(_:) does not accept
        // this hex form.
        parts.append(KeyNames.name(for: keyCode) ?? "0x\(String(keyCode, radix: 16))")
        return parts.joined(separator: "+")
    }
}

/// The ways a shortcut's text form can be wrong. Each case is specific
/// enough to tell the user what to fix; `unknownKey` additionally carries
/// the word that was not recognised, lowercased and trimmed.
public enum HotkeyParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The text was blank.
    case empty
    /// Only modifier names were given, for example `"ctrl+alt"`.
    case missingKey
    /// More than one key name was given, for example `"ctrl+a+b"`.
    case multipleKeys
    /// A word was neither a modifier name nor a key name. Carries the word.
    case unknownKey(String)

    /// The message shown to the user, after the config field name.
    public var description: String {
        switch self {
        case .empty:                return "is empty"
        case .missingKey:           return "has no key, only modifiers"
        case .multipleKeys:         return "names more than one key"
        case .unknownKey(let word): return "\"\(word)\" is not a key or modifier"
        }
    }
}

/// The key names a user may write in the config file, and the virtual key
/// code each one stands for.
///
/// A virtual key code is Apple's number for a physical key position, from
/// the `kVK_*` constants in `Events.h`. It names a position, not a
/// character: `0x00` is the key where A sits on a US keyboard, whatever
/// letter the current input source puts there. That is the kind of number
/// macOS's global hotkey API works with, and it is why this table lists
/// letters, digits, arrows, and function keys but almost no punctuation,
/// which moves around between keyboard layouts. The six exceptions are
/// `[`, `]` and `\`, the three keys right of P on a US keyboard
/// (`kVK_ANSI_LeftBracket`, `kVK_ANSI_RightBracket`, `kVK_ANSI_Backslash`),
/// `,` and `.`, the two keys right of M (`kVK_ANSI_Comma`,
/// `kVK_ANSI_Period`), and `` ` ``, the key left of 1 on the top row
/// (`kVK_ANSI_Grave`), because the default half, center, display and
/// Finder shortcuts sit on them; on another layout they are still those
/// six physical keys.
///
/// The numbers are copied here as literals so this library does not have
/// to import Carbon.
public enum KeyNames {
    /// The virtual key code for a name such as `"left"`, or nil if the
    /// name is not in the table.
    public static func keyCode(for name: String) -> UInt32? { byName[name] }

    /// The name for a virtual key code, or nil if the code is not in the
    /// table.
    public static func name(for keyCode: UInt32) -> String? { byCode[keyCode] }

    /// Every name in the table, for tests that check the whole table.
    static var allNames: [String] { Array(byName.keys) }

    private static let byName: [String: UInt32] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
        "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        // Digits on the top row (not the numeric keypad)
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
        // Named keys
        "return": 0x24, "tab": 0x30, "space": 0x31, "escape": 0x35,
        // The three keys right of P, the two right of M, and the one left
        // of 1, on a US keyboard.
        "[": 0x21, "]": 0x1E, "\\": 0x2A, ",": 0x2B, ".": 0x2F, "`": 0x32,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60,
        "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D,
        "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B, "f15": 0x71,
        "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
    ]

    private static let byCode: [UInt32: String] =
        Dictionary(uniqueKeysWithValues: byName.map { ($0.value, $0.key) })
}
