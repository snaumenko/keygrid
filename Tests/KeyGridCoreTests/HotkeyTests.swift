import Testing
import Carbon.HIToolbox   // Tests only. The library under test imports nothing;
                          // the tests compare its copied constants to Apple's.
@testable import KeyGridCore

// Virtual key codes used in assertions, as UInt32 from Apple's kVK_* constants.
private let kLeftArrow = UInt32(kVK_LeftArrow)
private let kReturn = UInt32(kVK_Return)
private let kDigit1 = UInt32(kVK_ANSI_1)
private let kDigit0 = UInt32(kVK_ANSI_0)
private let kSpace = UInt32(kVK_Space)
private let kF1 = UInt32(kVK_F1)
private let kF20 = UInt32(kVK_F20)

@Suite struct HotkeyParsing {
    @Test func canonicalString() throws {
        #expect(try Hotkey.parse("ctrl+alt+left") == Hotkey(modifiers: [.ctrl, .alt], keyCode: kLeftArrow))
    }

    // Case and spaces around `+` must not change the result.
    @Test func spacesAndCase() throws {
        #expect(try Hotkey.parse(" Ctrl + Alt + Left ") == Hotkey.parse("ctrl+alt+left"))
    }

    @Test func aliases() throws {
        #expect(try Hotkey.parse("command+option+1").modifiers == [.cmd, .alt])
        #expect(try Hotkey.parse("control+opt+space").modifiers == [.ctrl, .alt])
    }

    @Test func digitsBacktickAndSpace() throws {
        #expect(try Hotkey.parse("cmd+1").keyCode == kDigit1)
        #expect(try Hotkey.parse("cmd+0").keyCode == kDigit0)
        #expect(try Hotkey.parse("ctrl+alt+`").keyCode == UInt32(kVK_ANSI_Grave))
        #expect(try Hotkey.parse("ctrl+alt+space").keyCode == kSpace)
    }

    @Test func functionKeys() throws {
        #expect(try Hotkey.parse("f1").keyCode == kF1)
        #expect(try Hotkey.parse("f20").keyCode == kF20)
    }

    @Test func noModifiersIsAllowed() throws {
        #expect(try Hotkey.parse("return") == Hotkey(modifiers: [], keyCode: kReturn))
    }

    // Empty parts from doubled, leading, or trailing `+` are ignored.
    @Test func emptyPartsAreIgnored() throws {
        let expected = try Hotkey.parse("ctrl+a")
        #expect(try Hotkey.parse("ctrl++a") == expected)
        #expect(try Hotkey.parse("ctrl+a+") == expected)
        #expect(try Hotkey.parse("+ctrl+a") == expected)
        #expect(throws: HotkeyParseError.empty) { try Hotkey.parse("+") }
        #expect(throws: HotkeyParseError.empty) { try Hotkey.parse("") }
    }

    // A modifier given twice, or under two spellings, counts once.
    @Test func duplicateModifiersCollapse() throws {
        #expect(try Hotkey.parse("ctrl+ctrl+a") == Hotkey.parse("ctrl+a"))
        #expect(try Hotkey.parse("alt+option+opt+a").modifiers == [.alt])
    }

    @Test func partOrderDoesNotMatter() throws {
        #expect(try Hotkey.parse("a+ctrl") == Hotkey.parse("ctrl+a"))
        #expect(try Hotkey.parse("left+shift+cmd").description == "cmd+shift+left")
    }

    @Test func rejectsUnknownKey() {
        #expect(throws: HotkeyParseError.unknownKey("banana")) { try Hotkey.parse("ctrl+alt+banana") }
    }

    @Test func rejectsUnknownModifierLookingPart() {
        // "hyper" is neither a modifier nor a key; it is reported as an unknown key
        // because any non-modifier part is treated as the key.
        #expect(throws: HotkeyParseError.unknownKey("hyper")) { try Hotkey.parse("hyper+a") }
    }

    // The word in the error is lowercased and trimmed, because that is what
    // the parser compared against the table.
    @Test func unknownKeyReportsNormalisedWord() {
        #expect(throws: HotkeyParseError.unknownKey("enter")) { try Hotkey.parse("Ctrl+ Enter ") }
        #expect(throws: HotkeyParseError.unknownKey("f21")) { try Hotkey.parse("f21") }
        #expect(throws: HotkeyParseError.unknownKey("10")) { try Hotkey.parse("ctrl+10") }
        #expect(throws: HotkeyParseError.unknownKey("←")) { try Hotkey.parse("ctrl+←") }
    }

    @Test func rejectsMissingKey() {
        #expect(throws: HotkeyParseError.missingKey) { try Hotkey.parse("ctrl+alt") }
        #expect(throws: HotkeyParseError.missingKey) { try Hotkey.parse("command") }
    }

    @Test func rejectsTwoKeys() {
        #expect(throws: HotkeyParseError.multipleKeys) { try Hotkey.parse("ctrl+a+b") }
    }

    @Test func rejectsEmpty() {
        #expect(throws: HotkeyParseError.empty) { try Hotkey.parse("   ") }
    }
}

@Suite struct HotkeyDescription {
    @Test func canonicalOrder() throws {
        #expect(try Hotkey.parse("Alt+Cmd+Return").description == "cmd+alt+return")
        #expect(try Hotkey.parse("shift+ctrl+f5").description == "ctrl+shift+f5")
    }

    @Test(arguments: ["f1", "cmd+0", "shift+space", "cmd+ctrl+alt+shift+f20", "ctrl+alt+cmd+right"])
    func roundTrips(_ text: String) throws {
        let original = try Hotkey.parse(text)
        #expect(try Hotkey.parse(original.description) == original)
    }

    // A key code outside the table prints as hex. parse(_:) does not read
    // that form; it exists so the value is still readable in a message.
    @Test func unknownCodePrintsAsHex() {
        #expect(Hotkey(modifiers: [.cmd], keyCode: 0xFF).description == "cmd+0xff")
    }
}

@Suite struct ModifierFlags {
    // Each modifier alone, against Apple's constant, so swapping two bits
    // cannot pass unnoticed.
    @Test func eachModifierMapsToItsOwnCarbonBit() {
        #expect(Modifiers.cmd.carbonFlags == UInt32(cmdKey))
        #expect(Modifiers.shift.carbonFlags == UInt32(shiftKey))
        #expect(Modifiers.alt.carbonFlags == UInt32(optionKey))
        #expect(Modifiers.ctrl.carbonFlags == UInt32(controlKey))
    }

    @Test func combinedFlags() {
        #expect(Modifiers([.cmd, .shift]).carbonFlags == 0x300)
        #expect(Modifiers([.cmd, .ctrl, .alt, .shift]).carbonFlags == 0x1B00)
        #expect(Modifiers().carbonFlags == 0)
    }

    @Test func everyAliasPrintsUnderACanonicalName() {
        let printable = Set(Modifiers.canonicalOrder.map { $0.0 })
        for modifier in Modifiers.names.values {
            #expect(printable.contains(modifier))
        }
    }
}

@Suite struct KeyNameTable {
    @Test func lookupBothWays() {
        #expect(KeyNames.keyCode(for: "left") == kLeftArrow)
        #expect(KeyNames.name(for: kLeftArrow) == "left")
        #expect(KeyNames.keyCode(for: "nope") == nil)
    }

    // The whole table against Apple's kVK_* constants.
    @Test func everyCodeMatchesCarbon() {
        let carbon: [String: Int] = [
            "a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F, "h": kVK_ANSI_H,
            "g": kVK_ANSI_G, "z": kVK_ANSI_Z, "x": kVK_ANSI_X, "c": kVK_ANSI_C, "v": kVK_ANSI_V,
            "b": kVK_ANSI_B, "q": kVK_ANSI_Q, "w": kVK_ANSI_W, "e": kVK_ANSI_E, "r": kVK_ANSI_R,
            "y": kVK_ANSI_Y, "t": kVK_ANSI_T, "o": kVK_ANSI_O, "u": kVK_ANSI_U, "i": kVK_ANSI_I,
            "p": kVK_ANSI_P, "l": kVK_ANSI_L, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "n": kVK_ANSI_N,
            "m": kVK_ANSI_M,
            "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
            "return": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "escape": kVK_Escape,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "down": kVK_DownArrow, "up": kVK_UpArrow,
            "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "`": kVK_ANSI_Grave,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
            "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
            "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
            "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
        ]
        #expect(Set(KeyNames.allNames) == Set(carbon.keys))
        for (name, code) in carbon {
            #expect(KeyNames.keyCode(for: name) == UInt32(code), "\(name)")
        }
    }

    @Test func everyNameIsLowercaseAndRoundTrips() {
        for name in KeyNames.allNames {
            #expect(name == name.lowercased())
            #expect(KeyNames.name(for: KeyNames.keyCode(for: name)!) == name)
        }
    }
}
