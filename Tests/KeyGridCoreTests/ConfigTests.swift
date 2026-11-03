import Foundation   // Tests only, for JSONDecoder. KeyGridCore itself imports no framework.
import Testing
@testable import KeyGridCore

/// Decodes JSON text the way ConfigStore does: JSONDecoder into ConfigFile,
/// then validation into Config.
private func decode(_ json: String) throws -> Config {
    let file = try JSONDecoder().decode(ConfigFile.self, from: Data(json.utf8))
    return try Config(validating: file)
}

@Suite struct ConfigDefaults {
    @Test func defaultJSONDecodesToDefault() throws {
        #expect(try decode(Config.defaultJSON) == .default)
    }

    @Test func defaultValues() throws {
        #expect(Config.default.dockEnabled == true)
        #expect(Config.default.dockModifiers == [.ctrl, .alt])
        #expect(Config.default.dockHighlight == true)
        #expect(Config.default.windowBindings.count == WindowAction.allCases.count)
        #expect(try Config.default.windowBindings[.leftHalf] == Hotkey.parse("ctrl+alt+["))
        #expect(try Config.default.windowBindings[.sweepLeft] == Hotkey.parse("ctrl+alt+shift+left"))
        #expect(try Config.default.windowBindings[.moveLeft] == Hotkey.parse("ctrl+alt+left"))
    }

    // The file is the whole truth: a section the file does not have is off.
    @Test func emptyObjectBindsNothing() throws {
        let config = try decode("{}")
        #expect(config.dockEnabled == false)
        #expect(config.dockHighlight == false)
        #expect(config.windowBindings.isEmpty)
        #expect(config.allHotkeys.isEmpty)
    }

    @Test func emptyDockSectionIsDockDefaults() throws {
        let config = try decode(#"{"dock":{}}"#)
        #expect(config.dockEnabled == true)
        #expect(config.dockModifiers == [.ctrl, .alt])
        #expect(config.dockHighlight == true)
    }

    @Test func unknownKeysAreIgnored() throws {
        let config = try decode(#"{"future":1,"dock":{"enabled":true,"theme":"x"},"window":{"spiral":"cmd+s"}}"#)
        #expect(config.dockEnabled == true)
        #expect(config.windowBindings.isEmpty)
    }
}

@Suite struct WindowSection {
    // Config.default builds its bindings with `try!` from the strings
    // Config.defaultBinding(for:) returns, so each one must parse, and must
    // carry a modifier like any window hotkey.
    @Test(arguments: WindowAction.allCases)
    func defaultBindingParsesWithAModifier(_ action: WindowAction) throws {
        let hotkey = try Hotkey.parse(Config.defaultBinding(for: action))
        #expect(!hotkey.modifiers.isEmpty)
        #expect(Config.default.windowBindings[action] == hotkey)
    }

    @Test func missingSectionBindsNothing() throws {
        #expect(try decode(#"{"dock":{}}"#).windowBindings.isEmpty)
    }

    @Test func nullAndAbsentActionsAreUnbound() throws {
        // "full" is null; the thirteen actions not mentioned are absent.
        let config = try decode(#"{"window":{"full":null,"leftHalf":"ctrl+alt+left"}}"#)
        #expect(config.windowBindings[.full] == nil)
        #expect(config.windowBindings[.rightHalf] == nil)
        #expect(config.windowBindings.count == 1)
        #expect(try config.windowBindings[.leftHalf] == Hotkey.parse("ctrl+alt+left"))
    }

    // An empty string is a plausible way to "turn off" an action; it is an
    // error, because only null and absence mean unbound.
    @Test func emptyStringIsAnError() {
        #expect(throws: ConfigError.badHotkey(field: "window.full", reason: "is empty")) {
            try decode(#"{"window":{"full":""}}"#)
        }
    }

    @Test func badHotkeyNamesTheField() {
        #expect(throws: ConfigError.badHotkey(field: "window.sweepUp", reason: "\"upp\" is not a key or modifier")) {
            try decode(#"{"window":{"sweepUp":"ctrl+alt+shift+upp"}}"#)
        }
        #expect(throws: ConfigError.badHotkey(field: "window.full", reason: "has no key, only modifiers")) {
            try decode(#"{"window":{"full":"ctrl+alt"}}"#)
        }
        #expect(throws: ConfigError.badHotkey(field: "window.full", reason: "names more than one key")) {
            try decode(#"{"window":{"full":"ctrl+a+b"}}"#)
        }
    }

    @Test func bareKeyIsRejected() {
        #expect(throws: ConfigError.badHotkey(field: "window.full", reason: "needs at least one modifier")) {
            try decode(#"{"window":{"full":"k"}}"#)
        }
    }

    // Two bindings on one combo fail at decode time with both labels named.
    @Test func collisionWithDockNamesBothFields() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+1")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["dock.2", "window.full"])) {
            try decode(#"{"dock":{},"window":{"full":"ctrl+alt+1"}}"#)
        }
    }

    @Test func collisionWithFinderKeyIsDockOne() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+`")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["dock.1", "window.full"])) {
            try decode(#"{"dock":{},"window":{"full":"ctrl+alt+`"}}"#)
        }
    }

    @Test func collisionUsesTheConfiguredDockModifiers() throws {
        let hotkey = try Hotkey.parse("cmd+1")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["dock.2", "window.leftHalf"])) {
            try decode(#"{"dock":{"modifiers":"cmd"},"window":{"leftHalf":"cmd+1"}}"#)
        }
    }

    // Turning the Dock off is one way a user frees ctrl+alt+1 for a window
    // action (changing `dock.modifiers` is the other).
    @Test func disabledDockDoesNotCollide() throws {
        let config = try decode(#"{"dock":{"enabled":false},"window":{"full":"ctrl+alt+1"}}"#)
        #expect(config.allHotkeys.map(\.label) == ["window.full"])
    }

    @Test func collisionBetweenTwoActionsNamesBoth() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+left")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["window.leftHalf", "window.rightHalf"])) {
            try decode(#"{"window":{"leftHalf":"ctrl+alt+left","rightHalf":"alt+ctrl+left"}}"#)
        }
    }

    @Test func wrongJSONTypeNamesTheAction() {
        #expect {
            try decode(#"{"window":{"full":1}}"#)
        } throws: { error in
            guard case let DecodingError.typeMismatch(_, context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["window", "full"]
        }
    }
}

@Suite struct DockSection {
    @Test func modifiersCanBeCombined() throws {
        #expect(try decode(#"{"dock":{"modifiers":"ctrl+alt"}}"#).dockModifiers == [.ctrl, .alt])
        #expect(try decode(#"{"dock":{"modifiers":" Command + Shift "}}"#).dockModifiers == [.cmd, .shift])
    }

    @Test func modifiersMustNotContainAKey() {
        #expect(throws: ConfigError.badHotkey(field: "dock.modifiers", reason: "\"1\" is not a modifier")) {
            try decode(#"{"dock":{"modifiers":"cmd+1"}}"#)
        }
    }

    @Test func modifiersMustNotBeEmpty() {
        #expect(throws: ConfigError.badHotkey(field: "dock.modifiers", reason: "needs at least one modifier")) {
            try decode(#"{"dock":{"modifiers":""}}"#)
        }
    }

    // The keys sit ` 1…9 0 on the top row: the backtick is Finder, pinned
    // first in every Dock, the digit N is the Nth icon after Finder, and 0
    // is the eleventh icon.
    @Test func elevenHotkeysInDockOrder() throws {
        let hotkeys = Config.default.dockHotkeys
        #expect(hotkeys.count == 11)
        #expect(hotkeys.map(\.position) == Array(1...11))
        #expect(try hotkeys[0].hotkey == Hotkey.parse("ctrl+alt+`"))
        #expect(try hotkeys[1].hotkey == Hotkey.parse("ctrl+alt+1"))
        #expect(try hotkeys[9].hotkey == Hotkey.parse("ctrl+alt+9"))
        #expect(try hotkeys[10].hotkey == Hotkey.parse("ctrl+alt+0"))
    }

    @Test func hotkeysUseConfiguredModifiers() throws {
        let config = try decode(#"{"dock":{"modifiers":"cmd"}}"#)
        #expect(try config.dockHotkeys[0].hotkey == Hotkey.parse("cmd+`"))
        #expect(try config.dockHotkeys[2].hotkey == Hotkey.parse("cmd+2"))
        #expect(try config.dockHotkeys[10].hotkey == Hotkey.parse("cmd+0"))
    }

    @Test func disabledDockHasNoHotkeys() throws {
        #expect(try decode(#"{"dock":{"enabled":false}}"#).dockHotkeys.isEmpty)
        #expect(try decode(#"{"dock":{"enabled":false}}"#).allHotkeys.isEmpty)
    }

    // The border around the window a Dock shortcut brings forward is on
    // unless the file says otherwise; `null` reads as absent, like every
    // optional field.
    @Test func highlightIsOnUnlessTurnedOff() throws {
        #expect(try decode(#"{"dock":{"highlight":false}}"#).dockHighlight == false)
        #expect(try decode(#"{"dock":{"highlight":true}}"#).dockHighlight == true)
        #expect(try decode(#"{"dock":{"highlight":null}}"#).dockHighlight == true)
        #expect(try decode(#"{"dock":{"modifiers":"cmd"}}"#).dockHighlight == true)
    }

    // A string where a boolean belongs is malformed JSON for the decoder,
    // which reports the path, not a ConfigError.
    @Test func highlightMustBeABoolean() {
        #expect {
            try decode(#"{"dock":{"highlight":"yes"}}"#)
        } throws: { error in
            guard case DecodingError.typeMismatch(_, let context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["dock", "highlight"]
        }
    }
}

@Suite struct AllHotkeys {
    @Test func labelsNameTheConfigField() {
        let labels = Config.default.allHotkeys.map(\.label)
        let expected = (1...11).map { "dock.\($0)" } + WindowAction.allCases.map { "window.\($0.rawValue)" } + ["grid.hotkey"]
        #expect(labels == expected)
    }

    @Test func windowEntriesCarryTheParsedHotkey() throws {
        let entry = Config.default.allHotkeys.first { $0.label == "window.leftHalf" }
        #expect(try entry?.hotkey == Hotkey.parse("ctrl+alt+["))
    }

    // Nine actions of version 0.3.0 are gone. A file that still binds one
    // is refused by name, with the sweep actions that took over named
    // where there are any, so the person editing the file knows what to
    // write instead of silently losing the shortcut.
    @Test(arguments: [
        ("topHalf", "window.sweepUp and window.sweepDown"),
        ("bottomHalf", "window.sweepUp and window.sweepDown"),
        ("topLeftQuarter", "window.sweepLeft, window.sweepRight, window.sweepUp and window.sweepDown"),
        ("bottomRightQuarter", "window.sweepLeft, window.sweepRight, window.sweepUp and window.sweepDown"),
        ("leftThreeQuarters", "window.sweepLeft and window.sweepRight"),
        ("rightThreeQuarters", "window.sweepLeft and window.sweepRight"),
        ("otherDisplay", "window.nextDisplay and window.previousDisplay"),
    ])
    func removedActionIsRefusedByName(field: String, replacement: String) {
        #expect(throws: ConfigError.removedField(field: "window.\(field)", replacement: replacement)) {
            try decode(#"{"window":{"full":"ctrl+alt+return","\#(field)":"ctrl+alt+x"}}"#)
        }
    }

    @Test func anOldKeyStruckOutWithNullIsAsGoodAsDeleted() throws {
        #expect(try decode(#"{"window":{"otherDisplay":null}}"#).windowBindings.isEmpty)
    }

    // JSON key order is irrelevant; the order of the removed list in
    // `ConfigFile.Window.removedBindings` decides, and it is the order the
    // version 0.3.0 default file listed the actions.
    @Test func theFirstRemovedActionInTheOldDefaultOrderIsReported() {
        #expect(throws: ConfigError.removedField(field: "window.topHalf", replacement: "window.sweepUp and window.sweepDown")) {
            try decode(#"{"window":{"otherDisplay":"ctrl+alt+cmd+right","topHalf":"ctrl+alt+up"}}"#)
        }
    }

    // A removed action is reported before any hotkey is parsed, so a file
    // from version 0.3.0 gets the "what changed" message first.
    @Test func aRemovedActionWinsOverABadHotkey() {
        #expect(throws: ConfigError.removedField(field: "window.topHalf", replacement: "window.sweepUp and window.sweepDown")) {
            try decode(#"{"window":{"full":"nonsense","topHalf":"ctrl+alt+up"}}"#)
        }
    }
}

@Suite struct ConfigErrorText {
    @Test func readableMessages() throws {
        #expect(ConfigError.badHotkey(field: "dock.modifiers", reason: "x").description
                == "dock.modifiers: x")
        let hotkey = try Hotkey.parse("cmd+1")
        #expect(ConfigError.duplicateHotkey(hotkey, fields: ["dock.1", "grid.hotkey"]).description
                == "cmd+1 is bound twice: dock.1, grid.hotkey")
    }
}

@Suite struct UserTypos {
    // A wrong JSON type is rejected, and the error names the field, so
    // ConfigStore's message can point at it. A lenient decoder that quietly
    // fell back to the default would turn `"enabled": "yes"` into "on".
    @Test func wrongJSONTypeIsRejectedNamingTheField() {
        #expect {
            try decode(#"{"dock":{"enabled":"yes"}}"#)
        } throws: { error in
            guard case let DecodingError.typeMismatch(_, context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["dock", "enabled"]
        }
        #expect {
            try decode(#"{"dock":{"modifiers":["cmd"]}}"#)
        } throws: { error in
            guard case let DecodingError.typeMismatch(_, context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["dock", "modifiers"]
        }
    }

    @Test func nullSectionIsOffAndNullFieldIsDefault() throws {
        #expect(try decode(#"{"dock":null}"#).dockEnabled == false)
        let config = try decode(#"{"dock":{"enabled":null,"modifiers":null}}"#)
        #expect(config.dockEnabled == true)
        #expect(config.dockModifiers == [.ctrl, .alt])
    }

    @Test func blankModifiersAreRejected() {
        for text in ["", "   ", "+", " + "] {
            #expect(throws: ConfigError.badHotkey(field: "dock.modifiers", reason: "needs at least one modifier")) {
                try decode(#"{"dock":{"modifiers":"\#(text)"}}"#)
            }
        }
    }

    @Test func emptyPartsAndRepeatsCollapse() throws {
        #expect(try decode(#"{"dock":{"modifiers":"cmd+"}}"#).dockModifiers == .cmd)
        #expect(try decode(#"{"dock":{"modifiers":"cmd++alt"}}"#).dockModifiers == [.cmd, .alt])
        #expect(try decode(#"{"dock":{"modifiers":"cmd+command"}}"#).dockModifiers == .cmd)
    }

    // The file format is frozen at version 1: version 1 and a file with
    // no version key load; any other number is refused before the rest of
    // the file is read, even when the rest is valid.
    @Test func versionOneAndNoVersionLoad() throws {
        #expect(try decode(#"{"version":1,"dock":{}}"#).dockEnabled == true)
        #expect(try decode(#"{"dock":{}}"#).dockEnabled == true)
    }

    @Test func otherVersionsAreRefused() {
        for version in [0, 2, 99, -1] {
            #expect(throws: ConfigError.unsupportedVersion(version, supported: 1)) {
                try decode(#"{"version":\#(version),"dock":{}}"#)
            }
        }
    }

    // The version check runs before any other rule, so a file of another
    // format reports its version, not a field this build misreads.
    @Test func versionIsCheckedBeforeOtherFields() {
        #expect(throws: ConfigError.unsupportedVersion(2, supported: 1)) {
            try decode(#"{"version":2,"dock":{"modifiers":"nonsense"}}"#)
        }
    }

    @Test func unsupportedVersionMessage() {
        #expect(ConfigError.unsupportedVersion(2, supported: 1).description
                == "version: 2 is not supported; this KeyGrid reads version 1")
    }

    // `defaultJSON` writes the version this build reads.
    @Test func defaultJSONWritesFileVersion() throws {
        let file = try JSONDecoder().decode(ConfigFile.self, from: Data(Config.defaultJSON.utf8))
        #expect(file.version == Config.fileVersion)
    }
}

@Suite struct DefaultJSONText {
    @Test func endsWithExactlyOneNewline() {
        #expect(Config.defaultJSON.hasSuffix("\n"))
        #expect(!Config.defaultJSON.hasSuffix("\n\n"))
    }

    @Test func isPrettyPrintedForEditing() {
        let lines = Config.defaultJSON.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains(#""version": 1,"#))
        #expect(lines.contains(#""modifiers": "ctrl+alt","#))
        #expect(lines.contains(#""highlight": true"#))
        #expect(lines.contains(#""leftHalf": "ctrl+alt+[","#))
        #expect(lines.contains(#""sweepDown": "ctrl+alt+shift+down","#))
        #expect(lines.contains(#""moveDown": "ctrl+alt+down","#))
        #expect(lines.contains(#""nextDisplay": "ctrl+alt+.""#))
    }
}

@Suite struct DuplicateCheck {
    // Called directly with a hand-built list; the WindowSection suite covers
    // the check firing through Config(validating:).
    @Test func reportsBothFieldsSorted() throws {
        let hotkey = try Hotkey.parse("cmd+1")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["dock.1", "grid.hotkey"])) {
            try Config.checkForDuplicates(in: [(label: "grid.hotkey", hotkey: hotkey),
                                               (label: "dock.1", hotkey: hotkey)])
        }
    }

    @Test func distinctHotkeysPass() throws {
        try Config.checkForDuplicates(in: Config.default.allHotkeys)
    }

    // With two separate collisions the hotkey that appears first in the
    // list is reported, so the error text does not change between runs.
    @Test func firstHotkeyInListOrderIsReported() throws {
        let a = try Hotkey.parse("cmd+1")
        let b = try Hotkey.parse("cmd+2")
        #expect(throws: ConfigError.duplicateHotkey(a, fields: ["dock.1", "window.leftHalf"])) {
            try Config.checkForDuplicates(in: [(label: "dock.1", hotkey: a),
                                               (label: "dock.2", hotkey: b),
                                               (label: "window.full", hotkey: b),
                                               (label: "window.leftHalf", hotkey: a)])
        }
    }
}

@Suite struct GridSection {
    @Test func defaultGridHotkeyParses() throws {
        let hotkey = try Hotkey.parse(Config.defaultGridHotkey)
        #expect(!hotkey.modifiers.isEmpty)
        #expect(Config.default.grid?.hotkey == hotkey)
        #expect(Config.default.grid?.size == 6)
    }

    @Test func missingSectionMeansNoGrid() throws {
        #expect(try decode(#"{"dock":{}}"#).grid == nil)
    }

    // The size defaults; the hotkey does not, because the decoder cannot
    // tell an absent "hotkey" key from "hotkey": null, and null must keep
    // meaning "no shortcut" as it does for a window action.
    @Test func emptySectionIsDefaultSizeWithNoShortcut() throws {
        let grid = try #require(try decode(#"{"grid":{}}"#).grid)
        #expect(grid.hotkey == nil)
        #expect(grid.size == 6)
        // `null` for the size is the default too, unlike `null` for the hotkey.
        #expect(try decode(#"{"grid":{"size":null}}"#).grid?.size == 6)
    }

    @Test func wrongJSONTypeForSizeIsADecodingError() {
        #expect {
            try decode(#"{"grid":{"size":"6"}}"#)
        } throws: { error in
            guard case DecodingError.typeMismatch(_, let context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["grid", "size"]
        }
    }

    @Test func nullHotkeyKeepsTheGridWithoutAShortcut() throws {
        let config = try decode(#"{"grid":{"hotkey":null,"size":12}}"#)
        let grid = try #require(config.grid)
        #expect(grid.hotkey == nil)
        #expect(grid.size == 12)
        #expect(config.allHotkeys.isEmpty)
    }

    @Test func badHotkeyNamesTheField() {
        #expect(throws: ConfigError.badHotkey(field: "grid.hotkey", reason: "\"spce\" is not a key or modifier")) {
            try decode(#"{"grid":{"hotkey":"ctrl+alt+spce"}}"#)
        }
        #expect(throws: ConfigError.badHotkey(field: "grid.hotkey", reason: "needs at least one modifier")) {
            try decode(#"{"grid":{"hotkey":"space"}}"#)
        }
    }

    @Test(arguments: [0, 5, 7, 8, 16, 42, -6])
    func sizeNotInTheListNamesTheField(value: Int) {
        #expect(throws: ConfigError.notOneOf(field: "grid.size", value: value, allowed: [6, 12, 18, 24, 30, 36])) {
            try decode(#"{"grid":{"size":\#(value)}}"#)
        }
    }

    @Test(arguments: [6, 12, 18, 24, 30, 36])
    func everyListedSizeIsAccepted(value: Int) throws {
        #expect(try decode(#"{"grid":{"size":\#(value)}}"#).grid?.size == value)
    }

    // `columns` and `rows` were the size fields through version 0.3.0. A
    // file that still has one gets told the new name, even when it also
    // has a valid `size`, so the stale key does not linger unnoticed.
    @Test(arguments: ["columns", "rows"])
    func oldSizeFieldIsRejectedByName(field: String) throws {
        #expect(throws: ConfigError.removedField(field: "grid.\(field)", replacement: "grid.size")) {
            try decode(#"{"grid":{"\#(field)":6}}"#)
        }
        #expect(throws: ConfigError.removedField(field: "grid.\(field)", replacement: "grid.size")) {
            try decode(#"{"grid":{"size":6,"\#(field)":6}}"#)
        }
        // A key struck out with `null` is as good as deleted.
        #expect(try decode(#"{"grid":{"\#(field)":null}}"#).grid?.size == 6)
    }

    @Test func collisionWithADockShortcutNamesBoth() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+1")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["dock.2", "grid.hotkey"])) {
            try decode(#"{"dock":{},"grid":{"hotkey":"ctrl+alt+1"}}"#)
        }
    }

    @Test func collisionWithAWindowActionNamesBoth() throws {
        let hotkey = try Hotkey.parse("ctrl+alt+space")
        #expect(throws: ConfigError.duplicateHotkey(hotkey, fields: ["grid.hotkey", "window.full"])) {
            try decode(#"{"window":{"full":"ctrl+alt+space"},"grid":{"hotkey":"ctrl+alt+space"}}"#)
        }
    }

    @Test func allHotkeysEndsWithTheGridLabel() throws {
        let labels = Config.default.allHotkeys.map(\.label)
        #expect(labels.last == "grid.hotkey")
        #expect(labels.count == 11 + WindowAction.allCases.count + 1)
    }

    @Test func sizeErrorsReadAsSentences() {
        let notOneOf = ConfigError.notOneOf(field: "grid.size", value: 7, allowed: [6, 12, 18, 24, 30, 36])
        #expect("\(notOneOf)" == "grid.size: 7 is not one of 6, 12, 18, 24, 30, 36")
        let removed = ConfigError.removedField(field: "grid.columns", replacement: "grid.size")
        #expect("\(removed)" == "grid.columns was replaced by grid.size; remove grid.columns")
        let gone = ConfigError.removedField(field: "window.otherDisplay", replacement: nil)
        #expect("\(gone)" == "window.otherDisplay was removed; delete it from the file")
    }
}
