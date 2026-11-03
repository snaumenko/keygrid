/// The words the About window shows and the two bits of formatting it
/// needs. Pure text: no bundle, no window, no framework.
///
/// The description and the four promises are the README's own words,
/// repeated here so the app can show them. `README.md` is the master
/// copy: a unit test (`AboutTests`) reads the README from the repository
/// and checks that every line here appears in it, so one side cannot
/// change without the other. The version and the copyright are not here
/// because they live in `Resources/Info.plist`; `AboutWindow` reads them
/// from the bundle and only the formatting of the version is done here.
public enum About {
    /// The app's name as the window's headline. `CFBundleName` in
    /// `Resources/Info.plist` also holds the name; the constant exists so
    /// the Core tests can check the README's title without a bundle.
    public static let name = "KeyGrid"

    /// The README's first sentence.
    public static let description = "Keyboard-first window tiler and Dock switcher for macOS."

    /// The README's "What this app never does" list, in its order. The
    /// trust statement of the project; shown so a person who installed a
    /// build long ago can read what it promises without finding the README.
    public static let promises = [
        "No network code of any kind. No telemetry, no update checks.",
        "No third-party dependencies. Nothing downloaded at build time either.",
        "No permission other than Accessibility. Never Input Monitoring, Screen Recording, Notifications, Automation, or Full Disk Access.",
        "No settings anywhere but ~/.config/keygrid/config.json.",
    ]

    /// Where the source lives. Shown as a link the browser opens; the app
    /// never fetches it.
    public static let repository = "https://github.com/snaumenko/keygrid"

    /// `"0.4.0 (1)"` from the bundle's `CFBundleShortVersionString` and
    /// `CFBundleVersion`. Either may be missing or blank in a bundle
    /// assembled by hand: a missing build number is left out, and a
    /// missing version reads `"unknown version"` so the window never shows
    /// an empty line where the version belongs.
    public static func versionText(short: String?, build: String?) -> String {
        let short = short.map(trimmed) ?? ""
        let build = build.map(trimmed) ?? ""
        if short.isEmpty { return "unknown version" }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }

    /// One line about the running bundle's code signature. `identity` is
    /// the subject of the signing certificate (its name as Keychain Access
    /// shows it), or nil
    /// when the signature carries no certificate, which is what an ad-hoc
    /// signature (`codesign --sign -`, the Makefile's default) looks like.
    /// The ad-hoc line explains the symptom the README's "Signing and the
    /// Accessibility prompt" section is about: the grant is tied to the
    /// signature, and an ad-hoc signature changes with every build.
    public static func signatureText(identity: String?) -> String {
        if let identity = identity.map(trimmed), !identity.isEmpty {
            return "Signed by \(identity)."
        }
        return "Signed ad hoc: the Accessibility grant is lost on every rebuild."
    }

    private static func trimmed(_ text: String) -> String {
        Substring(text).trimmingWhitespace()
    }
}
