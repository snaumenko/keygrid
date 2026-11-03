/// The config file as written on disk, one field per JSON key, every
/// field optional.
///
/// This type is only a faithful copy of the JSON. It applies no defaults
/// and checks nothing; `Config(validating:)` does that. Keeping the two
/// apart means the JSON shape can be read off this struct, and the rules
/// can be read off `Config`.
///
/// `Codable` is part of the Swift standard library, not Foundation, so
/// conforming to it keeps this file framework-free, as every file in
/// `KeyGridCore` must be. The actual JSON decoding, which needs
/// Foundation, happens in the app (`ConfigStore`), which then calls
/// `Config(validating:)`. Every field is optional so that a missing key
/// is not a decoding error: `Config(validating:)` decides what it means
/// (a missing section is off; a missing field inside the `dock` section
/// takes its default; inside `grid`, a missing `size` takes its default
/// while a missing `hotkey` means no shortcut; a missing
/// window action is unbound). Keys the
/// program does not know are ignored, because Swift's synthesized
/// `Decodable` only looks up the keys it declares. That includes a
/// misspelled action name such as `"lefthalf"`, which leaves the action
/// unbound; the app logs the unbound actions after every reload so the
/// slip is visible in `log show`.
public struct ConfigFile: Codable, Equatable, Sendable {
    /// The file format's version. `Config(validating:)` accepts only
    /// `Config.fileVersion`, or no `version` key at all, which it reads as
    /// that version. Any other number is refused with
    /// `ConfigError.unsupportedVersion`.
    public var version: Int?
    /// Absent means the Dock shortcuts are off.
    public var dock: Dock?
    /// Absent means no window action is bound.
    public var window: Window?
    /// Absent means there is no grid overlay and no grid shortcut.
    public var grid: Grid?

    public struct Dock: Codable, Equatable, Sendable {
        /// Whether the Dock shortcuts (the backtick, the digits 1…9 and 0,
        /// each with `modifiers`) are registered at all.
        public var enabled: Bool?
        /// The modifier keys held with the backtick or digit, as text:
        /// `"ctrl+alt"` (the default) or `"cmd"`.
        public var modifiers: String?
        /// Whether a border is drawn around the focused window of the app
        /// a Dock shortcut brings forward. Absent means yes.
        public var highlight: Bool?
    }

    /// One optional hotkey string per `WindowAction`, under the same
    /// names. `null` and an absent key both mean "not bound". The nine
    /// fields after `nextDisplay` were actions through version 0.3.0 (the
    /// top and bottom halves, the quarters, the three-quarters, and the
    /// move to the other display); they are decoded only so that
    /// `Config(validating:)` can refuse a file that still binds one, with
    /// an error that names what replaced it.
    public struct Window: Codable, Equatable, Sendable {
        public var full: String?
        public var leftHalf: String?
        public var rightHalf: String?
        public var center: String?
        public var centerTwoThirds: String?
        public var sweepLeft: String?
        public var sweepRight: String?
        public var sweepUp: String?
        public var sweepDown: String?
        public var moveLeft: String?
        public var moveRight: String?
        public var moveUp: String?
        public var moveDown: String?
        public var previousDisplay: String?
        public var nextDisplay: String?
        public var topHalf: String?
        public var bottomHalf: String?
        public var topLeftQuarter: String?
        public var topRightQuarter: String?
        public var bottomLeftQuarter: String?
        public var bottomRightQuarter: String?
        public var leftThreeQuarters: String?
        public var rightThreeQuarters: String?
        public var otherDisplay: String?

        /// The hotkey text for one action, so validation can loop over
        /// `WindowAction.allCases` instead of naming fifteen fields.
        func binding(for action: WindowAction) -> String? {
            switch action {
            case .full:       return full
            case .leftHalf:   return leftHalf
            case .rightHalf:  return rightHalf
            case .center:     return center
            case .centerTwoThirds: return centerTwoThirds
            case .sweepLeft:  return sweepLeft
            case .sweepRight: return sweepRight
            case .sweepUp:    return sweepUp
            case .sweepDown:  return sweepDown
            case .moveLeft:   return moveLeft
            case .moveRight:  return moveRight
            case .moveUp:     return moveUp
            case .moveDown:   return moveDown
            case .previousDisplay: return previousDisplay
            case .nextDisplay:     return nextDisplay
            }
        }

        /// The removed actions still present in the file, each with the
        /// text `ConfigError.removedField` names as its replacement, in
        /// the order the old default file listed them. Empty for a file
        /// written for the current format.
        var removedBindings: [(field: String, replacement: String?)] {
            let sweeps = "window.sweepLeft, window.sweepRight, window.sweepUp and window.sweepDown"
            let vertical = "window.sweepUp and window.sweepDown"
            let horizontal = "window.sweepLeft and window.sweepRight"
            let old: [(String, String?, String?)] = [
                ("topHalf", topHalf, vertical),
                ("bottomHalf", bottomHalf, vertical),
                ("topLeftQuarter", topLeftQuarter, sweeps),
                ("topRightQuarter", topRightQuarter, sweeps),
                ("bottomLeftQuarter", bottomLeftQuarter, sweeps),
                ("bottomRightQuarter", bottomRightQuarter, sweeps),
                ("leftThreeQuarters", leftThreeQuarters, horizontal),
                ("rightThreeQuarters", rightThreeQuarters, horizontal),
                // nextDisplay does in one press what otherDisplay did, with
                // previousDisplay for the other way.
                ("otherDisplay", otherDisplay, "window.nextDisplay and window.previousDisplay"),
            ]
            return old.compactMap { name, value, replacement in
                value == nil ? nil : (field: "window.\(name)", replacement: replacement)
            }
        }
    }

    /// The grid overlay's shortcut and size as the file spells them: raw
    /// text and numbers, unchecked. `Config.Grid` is the checked form.
    /// `hotkey` absent or `null` keeps the grid configured but unbound;
    /// `size` takes its default when absent and must be one of
    /// `Config.Grid.sizes`. `columns` and `rows` were the size fields
    /// through version 0.3.0; they are decoded only so that
    /// `Config(validating:)` can reject a file that still has them with an
    /// error naming `size` as the replacement.
    public struct Grid: Codable, Equatable, Sendable {
        public var hotkey: String?
        public var size: Int?
        public var columns: Int?
        public var rows: Int?
    }

    public init(version: Int? = nil, dock: Dock? = nil, window: Window? = nil, grid: Grid? = nil) {
        self.version = version
        self.dock = dock
        self.window = window
        self.grid = grid
    }
}

/// The program's settings after defaults have been filled in and the
/// file's values checked. Everything that reads settings reads this type;
/// nothing reads `ConfigFile` except the validation step.
///
/// A `Config` can only be made in two ways: `Config.default`, or
/// `Config(validating:)` from a `ConfigFile`. Every hotkey in
/// `allHotkeys` is distinct and has at least one modifier, so no shortcut
/// is a bare key that would steal typing from the app in front.
/// `Config(validating:)` checks both rules; for `Config.default` the unit
/// tests check them. The fields cannot be changed from outside, so the
/// rules hold for the life of the value.
///
/// The file is the whole truth: when `config.json` exists, a section it
/// does not contain is off. No `dock` section means no Dock shortcuts; no
/// `window` section means no window bindings; no `grid` section means no
/// grid overlay. Only when the file does not exist at all does the app
/// write `defaultJSON` and run with it.
public struct Config: Equatable, Sendable {
    /// Whether the Dock shortcuts are registered. Off, they do nothing and
    /// the backtick and the digits reach the app in front as usual.
    public private(set) var dockEnabled: Bool
    /// Held with the backtick (Finder) or a digit 1…9, 0 (the icons after
    /// Finder) to pick a Dock position. Never empty.
    public private(set) var dockModifiers: Modifiers
    /// Whether the app draws a border around the focused window of the
    /// app a Dock shortcut brought forward, so the eye finds it. On by
    /// default; `dock.highlight: false` turns it off. False when the file
    /// has no `dock` section at all, which also means no Dock shortcuts.
    public private(set) var dockHighlight: Bool
    /// The window actions that have a hotkey. An action missing from the
    /// dictionary is unbound and gets no shortcut.
    public private(set) var windowBindings: [WindowAction: Hotkey]
    /// The grid overlay's shortcut and size; nil when the file has no
    /// `grid` section, and then no grid exists.
    public private(set) var grid: Grid?

    /// How the grid overlay is summoned and how fine it is. `Config.Grid`
    /// holds the values after `Config(validating:)` has checked them; it
    /// draws nothing and computes no frames. `GridOverlay` reads it and
    /// `Geometry.gridLayout(for:size:)` turns `size` into a column and
    /// row count for one display.
    public struct Grid: Equatable, Sendable {
        /// The shortcut that shows the overlay, or nil when the file's
        /// `hotkey` is `null` or absent: the grid is configured but has no
        /// shortcut.
        public let hotkey: Hotkey?
        /// Cells along the shorter edge of a display, one of `sizes`. The
        /// count along the longer edge is derived from the display's shape
        /// by `Geometry.gridLayout(for:size:)`, so the file holds one
        /// number and a portrait display gets the same grid turned on its
        /// side.
        public let size: Int
        /// The values `size` may take: multiples of 6, so halves and thirds
        /// of the short edge fall on cell edges, from 6 to 36. 36 on the
        /// short edge of a 1600-point display still leaves 44-point cells,
        /// a comfortable target for a mouse drag. The request was "ideally
        /// a multiple of 6, at least 6"; refusing other values was chosen
        /// over accepting them because halves and thirds on cell edges are
        /// the whole point of the number, and an error naming the field is
        /// clearer than a grid that silently cannot do thirds.
        public static let sizes = [6, 12, 18, 24, 30, 36]

        /// Internal so only `Config.default` (literal 6, in `sizes`) and
        /// `Config(validating:)` (after `checkSize`) build one.
        init(hotkey: Hotkey?, size: Int) {
            self.hotkey = hotkey
            self.size = size
        }
    }

    public static let `default` = Config(
        dockEnabled: true,
        dockModifiers: defaultDockModifiers,
        dockHighlight: true,
        windowBindings: Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { action in
            // Every default binding is a literal in defaultBinding(for:) and
            // the test defaultBindingParsesWithAModifier parses each one, so
            // the `try!` cannot fail.
            (action, try! Hotkey.parse(Config.defaultBinding(for: action)))
        }),
        // `ctrl+alt+space` is parsed in the test defaultGridHotkeyParses,
        // so the `try!` cannot fail. Space is free of the window actions
        // and under the thumb while the other hand reaches for the mouse.
        grid: Grid(hotkey: try! Hotkey.parse(Config.defaultGridHotkey),
                   size: Config.defaultGridSize))

    /// The Dock default: ⌃⌥ with the backtick and the digits. Every
    /// built-in default holds ⌃⌥ (Dock ⌃⌥` and ⌃⌥1, placements ⌃⌥⏎ and
    /// ⌃⌥[, sweeps ⌃⌥⇧←, grid ⌃⌥Space) because few app menus use ⌃⌥
    /// while ⌘1…⌘9 switch tabs in most browsers and a global hotkey takes
    /// the key away from the app in front. `docs/ARCHITECTURE.md`, "How a
    /// hotkey travels", states the rule.
    static let defaultDockModifiers: Modifiers = [.ctrl, .alt]

    /// The grid defaults. `Config.default` uses both; a present `grid`
    /// section that leaves `size` out gets the size default, while a
    /// left-out `hotkey` means no shortcut. Size 6 is the coarsest grid
    /// that still offers halves and thirds along the short edge; on a 16:9
    /// display it draws 12×6 cells (`Geometry.gridLayout(for:size:)`).
    static let defaultGridHotkey = "ctrl+alt+space"
    public static let defaultGridSize = 6

    /// The one file format this build reads, frozen at 1.0.0. A key may
    /// be added under version 1 when a file without it still means what
    /// it meant; renaming, removing, or changing the meaning of a key
    /// raises the number. `defaultJSON` writes this number, and a test
    /// checks that the two agree.
    public static let fileVersion = 1

    /// The hotkey text `Config.default` binds to each window action. The
    /// moves are ⌃⌥ with the arrow that names their direction and the
    /// sweeps add ⇧ to the same arrow; the display jumps are ⌃⌥ with `,`
    /// and `.`, the keys whose caps also show `<` and `>` (issue 62). The placements
    /// are ⌃⌥ with Return
    /// for full, the bracket keys for the halves (`[` left, `]` right) and
    /// backslash for center, with ⇧ added for center at two thirds, as the
    /// owner chose (issues 53 and 56).
    /// Internal rather than private so a test can parse every entry.
    static func defaultBinding(for action: WindowAction) -> String {
        switch action {
        case .full:       return "ctrl+alt+return"
        case .leftHalf:   return "ctrl+alt+["
        case .rightHalf:  return "ctrl+alt+]"
        case .center:     return "ctrl+alt+\\"
        case .centerTwoThirds: return "ctrl+alt+shift+\\"
        case .sweepLeft:  return "ctrl+alt+shift+left"
        case .sweepRight: return "ctrl+alt+shift+right"
        case .sweepUp:    return "ctrl+alt+shift+up"
        case .sweepDown:  return "ctrl+alt+shift+down"
        case .moveLeft:   return "ctrl+alt+left"
        case .moveRight:  return "ctrl+alt+right"
        case .moveUp:     return "ctrl+alt+up"
        case .moveDown:   return "ctrl+alt+down"
        case .previousDisplay: return "ctrl+alt+,"
        case .nextDisplay:     return "ctrl+alt+."
        }
    }

    /// The text written to `config.json` on first launch. Decoding and
    /// validating it gives exactly `Config.default`; a test checks that.
    /// The backslash in the center shortcuts is written `\\\\` here: Swift
    /// turns that into `\\` in the string, which is how JSON spells one
    /// backslash, so the file reads `"ctrl+alt+\\"`.
    public static let defaultJSON = """
    {
      "version": 1,
      "dock": {
        "enabled": true,
        "modifiers": "ctrl+alt",
        "highlight": true
      },
      "window": {
        "full": "ctrl+alt+return",
        "leftHalf": "ctrl+alt+[",
        "rightHalf": "ctrl+alt+]",
        "center": "ctrl+alt+\\\\",
        "centerTwoThirds": "ctrl+alt+shift+\\\\",
        "sweepLeft": "ctrl+alt+shift+left",
        "sweepRight": "ctrl+alt+shift+right",
        "sweepUp": "ctrl+alt+shift+up",
        "sweepDown": "ctrl+alt+shift+down",
        "moveLeft": "ctrl+alt+left",
        "moveRight": "ctrl+alt+right",
        "moveUp": "ctrl+alt+up",
        "moveDown": "ctrl+alt+down",
        "previousDisplay": "ctrl+alt+,",
        "nextDisplay": "ctrl+alt+."
      },
      "grid": {
        "hotkey": "ctrl+alt+space",
        "size": 6
      }
    }

    """

    private init(dockEnabled: Bool, dockModifiers: Modifiers, dockHighlight: Bool, windowBindings: [WindowAction: Hotkey], grid: Grid?) {
        self.dockEnabled = dockEnabled
        self.dockModifiers = dockModifiers
        self.dockHighlight = dockHighlight
        self.windowBindings = windowBindings
        self.grid = grid
    }

    /// Builds the settings from a decoded file, then checks the rules.
    /// Throws `ConfigError` naming the JSON field at fault.
    ///
    /// A `version` other than `fileVersion` is refused first, with
    /// `ConfigError.unsupportedVersion`; a missing `version` is read as
    /// `fileVersion`, so a file written by hand does not need one.
    ///
    /// A section that is absent is off. Inside a present `dock` section a
    /// missing field takes its default (`enabled` true, `modifiers`
    /// `defaultDockModifiers`, that is `ctrl+alt`, `highlight` true); inside a present
    /// `window` section a missing action is
    /// unbound, and an action that version 0.3.0 had and this version does
    /// not (the nine fields after `nextDisplay` on `ConfigFile.Window`) is
    /// refused with `ConfigError.removedField` before any hotkey is parsed;
    /// inside a present `grid` section a missing `size` takes its
    /// default (`defaultGridSize`) while a missing or `null` `hotkey`
    /// leaves the grid without a shortcut. A `grid` section that still has
    /// `columns` or `rows`, the size fields through version 0.3.0, is
    /// rejected with `ConfigError.removedField` so the person editing the
    /// file learns the new name instead of getting the default silently.
    public init(validating file: ConfigFile) throws {
        // Checked before anything else: in a file of another format, the
        // other fields may mean something this build does not know.
        if let version = file.version, version != Config.fileVersion {
            throw ConfigError.unsupportedVersion(version, supported: Config.fileVersion)
        }

        if let dock = file.dock {
            dockEnabled = dock.enabled ?? true
            if let text = dock.modifiers {
                dockModifiers = try Config.parseModifiers(text, field: "dock.modifiers")
            } else {
                dockModifiers = Config.defaultDockModifiers
            }
            dockHighlight = dock.highlight ?? true
        } else {
            dockEnabled = false
            // `dockHotkeys` returns nothing while `dockEnabled` is false, so
            // this value is only visible to code that reads `dockModifiers`
            // directly; set so it is never a surprise.
            dockModifiers = Config.defaultDockModifiers
            // No Dock shortcuts, so no switch to highlight.
            dockHighlight = false
        }

        windowBindings = [:]
        if let window = file.window {
            if let removed = window.removedBindings.first {
                throw ConfigError.removedField(field: removed.field, replacement: removed.replacement)
            }
            for action in WindowAction.allCases {
                guard let text = window.binding(for: action) else { continue }
                windowBindings[action] = try Config.parseHotkey(text, field: "window.\(action.rawValue)")
            }
        }

        if let section = file.grid {
            // A decoded `hotkey` is nil both when the key is absent and when
            // it is `null`; Swift's synthesized Decodable cannot tell them
            // apart. Both mean "no shortcut", as they do for a window action.
            // The size defaults instead because a grid without a size is
            // meaningless, while a struck-out shortcut is a choice.
            let hotkey = try section.hotkey.map { try Config.parseHotkey($0, field: "grid.hotkey") }
            if section.columns != nil {
                throw ConfigError.removedField(field: "grid.columns", replacement: "grid.size")
            }
            if section.rows != nil {
                throw ConfigError.removedField(field: "grid.rows", replacement: "grid.size")
            }
            let size = try Config.checkSize(section.size ?? Config.defaultGridSize)
            grid = Grid(hotkey: hotkey, size: size)
        } else {
            grid = nil
        }

        try Config.checkForDuplicates(in: allHotkeys)
    }

    /// The Dock shortcuts in order: position 1 (Finder, which macOS pins
    /// first in every Dock) is `` <modifiers>+` ``, positions 2 to 10 are
    /// `<modifiers>+1` to `<modifiers>+9`, and position 11 is
    /// `<modifiers>+0`. The keys sit `` ` `` 1…9 0 left to right on the
    /// top row, so the Nth key reaches the Nth icon, and the digit N
    /// reaches the Nth icon after Finder, which is how people count their
    /// Dock. Empty when `dockEnabled` is false.
    public var dockHotkeys: [(position: Int, hotkey: Hotkey)] {
        guard dockEnabled else { return [] }
        let keys = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        return keys.enumerated().map { index, key in
            // Every key here is in the KeyNames table, so the lookup cannot fail.
            let keyCode = KeyNames.keyCode(for: key)!
            return (position: index + 1, hotkey: Hotkey(modifiers: dockModifiers, keyCode: keyCode))
        }
    }

    /// Every shortcut the program registers, each with the name of the
    /// config field it came from: `dock.1` … `dock.11`, then
    /// `window.full` … `window.nextDisplay` in `WindowAction` order, then
    /// `grid.hotkey` when the grid has one. Error messages and the
    /// duplicate check use these labels. No two entries share a hotkey.
    public var allHotkeys: [(label: String, hotkey: Hotkey)] {
        let dock = dockHotkeys.map { (label: "dock.\($0.position)", hotkey: $0.hotkey) }
        let window = WindowAction.allCases.compactMap { action in
            windowBindings[action].map { (label: "window.\(action.rawValue)", hotkey: $0) }
        }
        let grid = (self.grid?.hotkey).map { [(label: "grid.hotkey", hotkey: $0)] } ?? []
        return dock + window + grid
    }

    /// Returns `value` if it is one of `Config.Grid.sizes`, otherwise throws
    /// `ConfigError.notOneOf` naming `grid.size`.
    private static func checkSize(_ value: Int) throws -> Int {
        guard Grid.sizes.contains(value) else {
            throw ConfigError.notOneOf(field: "grid.size", value: value, allowed: Grid.sizes)
        }
        return value
    }

    /// Reads a full shortcut such as `"ctrl+alt+left"` for a config field
    /// and requires at least one modifier: a bare key bound as a global
    /// shortcut would take that key away from every app. Parse errors are
    /// rewrapped as `ConfigError.badHotkey` so the message names the field.
    private static func parseHotkey(_ text: String, field: String) throws -> Hotkey {
        let hotkey: Hotkey
        do {
            hotkey = try Hotkey.parse(text)
        } catch {
            throw ConfigError.badHotkey(field: field, reason: "\(error)")
        }
        guard !hotkey.modifiers.isEmpty else {
            throw ConfigError.badHotkey(field: field, reason: "needs at least one modifier")
        }
        return hotkey
    }

    /// Reads modifier names joined by `+`, for example `"ctrl+alt"`. Unlike
    /// `Hotkey.parse`, a key name is an error here and at least one
    /// modifier is required.
    private static func parseModifiers(_ text: String, field: String) throws -> Modifiers {
        var modifiers = Modifiers()
        for part in text.lowercased().split(separator: "+") {
            let name = part.trimmingWhitespace()
            if name.isEmpty { continue }
            guard let modifier = Modifiers.names[name] else {
                throw ConfigError.badHotkey(field: field, reason: "\"\(name)\" is not a modifier")
            }
            modifiers.insert(modifier)
        }
        guard !modifiers.isEmpty else {
            throw ConfigError.badHotkey(field: field, reason: "needs at least one modifier")
        }
        return modifiers
    }

    /// Throws `duplicateHotkey` if two labels map to the same hotkey, for
    /// example `dock.2` and `window.full` both on `ctrl+alt+1`. The second loop
    /// walks `hotkeys` in list order rather than iterating `seen`, because
    /// Swift dictionaries have no fixed iteration order: when several
    /// hotkeys are each bound twice, the one that appears first in
    /// `hotkeys` is reported, so the message is the same on every run. The
    /// labels are sorted for the same reason. Internal rather than private
    /// so a test can call it with hand-built lists.
    static func checkForDuplicates(in hotkeys: [(label: String, hotkey: Hotkey)]) throws {
        var seen: [Hotkey: [String]] = [:]
        for entry in hotkeys {
            seen[entry.hotkey, default: []].append(entry.label)
        }
        for entry in hotkeys {
            let labels = seen[entry.hotkey]!
            if labels.count > 1 {
                throw ConfigError.duplicateHotkey(entry.hotkey, fields: labels.sorted())
            }
        }
    }
}

/// What can be wrong with a config file beyond malformed JSON (which the
/// decoder in the app reports on its own). Each case names the JSON field
/// so the message tells the user where to look.
public enum ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A hotkey or modifier string in `field` could not be read; `reason`
    /// says why in words.
    case badHotkey(field: String, reason: String)
    /// The same shortcut is bound in more than one field.
    case duplicateHotkey(Hotkey, fields: [String])
    /// A number in `field` is not in the short list of values the program
    /// accepts there.
    case notOneOf(field: String, value: Int, allowed: [Int])
    /// `field` was dropped from the file format. `replacement` names what
    /// does its job now, as text for the message ("grid.size",
    /// "window.sweepUp and window.sweepDown"), or nil when nothing does.
    case removedField(field: String, replacement: String?)
    /// The file's `version` is not the one file format this build reads,
    /// `supported` (`Config.fileVersion`).
    case unsupportedVersion(Int, supported: Int)

    public var description: String {
        switch self {
        case .badHotkey(let field, let reason):
            return "\(field): \(reason)"
        case .notOneOf(let field, let value, let allowed):
            return "\(field): \(value) is not one of \(allowed.map(String.init).joined(separator: ", "))"
        case .removedField(let field, let replacement):
            if let replacement {
                return "\(field) was replaced by \(replacement); remove \(field)"
            }
            return "\(field) was removed; delete it from the file"
        case .unsupportedVersion(let version, let supported):
            return "version: \(version) is not supported; this KeyGrid reads version \(supported)"
        case .duplicateHotkey(let hotkey, let fields):
            return "\(hotkey) is bound twice: \(fields.joined(separator: ", "))"
        }
    }
}

extension Substring {
    /// Removes whitespace from both ends. Used by `Hotkey.parse` and
    /// `Config.parseModifiers`. Written out because this library imports
    /// no framework, so Foundation's `trimmingCharacters` is not available.
    func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
