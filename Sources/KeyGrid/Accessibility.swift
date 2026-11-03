import AppKit
import ApplicationServices
import os

/// The Accessibility permission: whether macOS lets this app read and
/// control other apps' user interfaces, and how to ask for it.
///
/// KeyGrid needs the permission for two things: reading the Dock's list
/// of icons (`DockSwitcher`), and moving other apps' windows
/// (`WindowMover`). It is the only permission the app ever asks for.
/// Global shortcuts do not need it.
///
/// macOS ties the grant to the app's code signature. An ad-hoc signed
/// build (the Makefile default) gets a new signature on every rebuild, so
/// the permission may have to be granted again; `SIGN_IDENTITY` in the
/// Makefile keeps the signature stable. macOS posts no documented
/// notification when the user changes the grant, so callers that care
/// re-ask `isTrusted(prompt: false)` on a timer.
enum Accessibility {
    private static let log = Logger(subsystem: "com.keygrid.app", category: "accessibility")

    /// Whether the permission is granted right now. With `prompt: true`,
    /// macOS also shows its own dialog pointing the user to System
    /// Settings; it shows that dialog on every call while the permission
    /// is missing, so pass `true` once at launch and `false` on the timer.
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings at Privacy & Security → Accessibility, where
    /// the user can turn the permission on for KeyGrid. Logs if macOS
    /// refuses the URL, which would mean Apple changed the pane's address.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url) {
            log.error("could not open System Settings at Privacy & Security → Accessibility; open it by hand")
        }
    }
}
