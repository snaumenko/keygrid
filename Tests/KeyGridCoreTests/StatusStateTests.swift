import Testing
@testable import KeyGridCore

@Suite struct ResolvingTheState {
    @Test func everythingFineIsOk() {
        #expect(StatusState.resolve(accessibilityGranted: true, configError: nil, hotkeyFailures: []) == .ok)
        // An empty config error and blank failure lines are not problems.
        #expect(StatusState.resolve(accessibilityGranted: true, configError: "", hotkeyFailures: [""]) == .ok)
    }

    @Test func aMissingPermissionWinsOverEverything() {
        #expect(StatusState.resolve(accessibilityGranted: false, configError: nil, hotkeyFailures: []) == .needsAccessibility)
        #expect(StatusState.resolve(accessibilityGranted: false, configError: "bad", hotkeyFailures: ["x"]) == .needsAccessibility)
    }

    @Test func aConfigErrorIsAProblem() {
        #expect(StatusState.resolve(accessibilityGranted: true, configError: "grid.size: 7", hotkeyFailures: []) == .problem("grid.size: 7"))
    }

    @Test func aConfigErrorWinsOverFailedShortcuts() {
        #expect(StatusState.resolve(accessibilityGranted: true, configError: "bad file", hotkeyFailures: ["window.full: taken"]) == .problem("bad file"))
    }

    @Test func whitespaceOnlyInputIsNotAProblemForEither() {
        // `resolve` and `errorLine` read their inputs the same way.
        #expect(StatusState.resolve(accessibilityGranted: true, configError: "\n  \n", hotkeyFailures: [" "]) == .ok)
        #expect(StatusState.errorLine(configError: "\n  \n", hotkeyFailures: [" "]) == nil)
    }

    @Test func failedShortcutsAreAProblemOneLineEach() {
        let state = StatusState.resolve(accessibilityGranted: true, configError: nil, hotkeyFailures: ["window.full: taken", "grid.hotkey: taken"])
        #expect(state == .problem("window.full: taken\ngrid.hotkey: taken"))
    }
}

@Suite struct TheErrorLine {
    @Test func nothingWrongHasNoLine() {
        #expect(StatusState.errorLine(configError: nil, hotkeyFailures: []) == nil)
        #expect(StatusState.errorLine(configError: "", hotkeyFailures: [""]) == nil)
    }

    @Test func aConfigErrorGetsItsPrefix() {
        #expect(StatusState.errorLine(configError: "grid.size: 7 is not one of 6, 12", hotkeyFailures: [])
                == "Config error: grid.size: 7 is not one of 6, 12")
    }

    @Test func aLongConfigErrorShowsItsFirstLineAndACount() {
        #expect(StatusState.errorLine(configError: "first\nsecond\nthird", hotkeyFailures: []) == "Config error: first (+2 more)")
    }

    @Test func failedShortcutsShowTheFirstAndACount() {
        #expect(StatusState.errorLine(configError: nil, hotkeyFailures: ["window.full: taken"]) == "Shortcut failed: window.full: taken")
        #expect(StatusState.errorLine(configError: nil, hotkeyFailures: ["a", "b"]) == "Shortcut failed: a (+1 more)")
    }

    @Test func aLongProblemIsCutWithAnEllipsis() {
        let long = String(repeating: "x", count: 200)
        let line = StatusState.errorLine(configError: long, hotkeyFailures: [])
        #expect(line == "Config error: " + String(repeating: "x", count: StatusState.maxShown - 1) + "…")
        // Exactly the limit is shown whole.
        let fits = String(repeating: "y", count: StatusState.maxShown)
        #expect(StatusState.errorLine(configError: nil, hotkeyFailures: [fits]) == "Shortcut failed: " + fits)
    }

    @Test func theConfigErrorComesBeforeFailedShortcuts() {
        #expect(StatusState.errorLine(configError: "bad file", hotkeyFailures: ["x"]) == "Config error: bad file")
    }
}
