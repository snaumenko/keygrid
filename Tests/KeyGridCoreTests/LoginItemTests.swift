import Testing
@testable import KeyGridCore

@Suite struct LoginItemMenuText {
    @Test func offAndOnShareTheTitleAndDifferByTheCheckmark() {
        #expect(LoginItemState.off.menuTitle == "Launch at Login")
        #expect(LoginItemState.on.menuTitle == "Launch at Login")
        #expect(LoginItemState.off.isChecked == false)
        #expect(LoginItemState.on.isChecked == true)
    }

    @Test func approvalIsAskedForInTheTitleWithoutACheckmark() {
        #expect(LoginItemState.needsApproval.menuTitle == "Launch at Login: approve in System Settings…")
        #expect(LoginItemState.needsApproval.isChecked == false)
        #expect(LoginItemState.needsApproval.isEnabled == true)
    }

    @Test func unavailableIsTheOnlyDisabledState() {
        #expect(LoginItemState.unavailable.menuTitle == "Launch at Login: unavailable")
        #expect(LoginItemState.unavailable.isEnabled == false)
        #expect(LoginItemState.unavailable.isChecked == false)
        for state in [LoginItemState.off, .on, .needsApproval] {
            #expect(state.isEnabled, "\(state)")
        }
    }

    // Every title starts with "Launch at Login", so the item is found in
    // one place of the menu whatever the state.
    @Test func everyTitleStartsWithLaunchAtLogin() {
        for state in [LoginItemState.off, .on, .needsApproval, .unavailable] {
            #expect(state.menuTitle.hasPrefix("Launch at Login"), "\(state)")
        }
    }
}
