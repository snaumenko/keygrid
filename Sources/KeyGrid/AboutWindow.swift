import AppKit
import Security
import KeyGridCore

/// The window behind the status menu's "About KeyGrid" item: the icon,
/// the name and version, the one-line description, the four things the
/// app never does, the config file's path, the Accessibility state, who
/// signed the running bundle, a link to the source, and the copyright
/// line.
///
/// One window, reused: `show` creates it on the first call and brings it
/// forward on later ones, rebuilding the text each time so the
/// Accessibility line is current. KeyGrid is a menu-bar-only app
/// (`LSUIElement` in `Info.plist`), and a window of such an app does not
/// come forward unless the app activates itself, so `show` activates
/// KeyGrid and `windowWillClose` activates the app that was in front
/// before, so closing About puts the user back where they were. While
/// About is open, every activation of another app is noted, so a user
/// who switches to Terminal, works, and then closes About lands in
/// Terminal, not in the app they came from an hour ago.
///
/// The words come from `About` in `KeyGridCore` (the README's words,
/// checked against it by a test), the version and copyright from the
/// bundle's `Info.plist`, the config path from `ConfigStore.file`, and
/// the signature from the Security framework. This type opens nothing but
/// the window: the repository link is opened by AppKit in the browser
/// when clicked, and nothing is fetched. It stores nothing.
final class AboutWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// The app to give focus back to when the window closes: the app in
    /// front when the window was opened, replaced by any other app the
    /// user activates while the window is open. Nil while the window is
    /// closed.
    private var previousApp: NSRunningApplication?
    /// The registration for `NSWorkspace.didActivateApplicationNotification`
    /// that keeps `previousApp` current while the window is open; nil
    /// while it is closed.
    private var activationObserver: NSObjectProtocol?

    /// The width of the text column, in points: wide enough for the
    /// longest promise to wrap onto two lines, narrow enough to read as a
    /// panel rather than a document.
    private static let contentWidth: CGFloat = 360
    /// The space between the text and the window's edge, on every side.
    private static let margin: CGFloat = 20
    /// The icon's side, in points.
    private static let iconSide: CGFloat = 64

    /// Opens the window, or brings it forward if it is open.
    /// `accessibilityGranted` is the value `AppController` keeps for the
    /// menu's icon; it is shown as read now and not refreshed while the
    /// window stays open.
    func show(accessibilityGranted: Bool) {
        let window = self.window ?? makeWindow()
        self.window = window
        // A closed window is kept (`isReleasedWhenClosed` is false), so
        // "opening" is "the window is not on screen", not "no window yet".
        let opening = !window.isVisible
        if opening {
            previousApp = NSWorkspace.shared.frontmostApplication
            startNotingActivations()
        }
        let content = Self.makeContent(accessibilityGranted: accessibilityGranted)
        window.contentView = content
        window.setContentSize(NSSize(width: Self.contentWidth + 2 * Self.margin, height: content.fittingSize.height))
        // Centered after the content gave the window its height; a window
        // centered before that would keep its bottom edge and grow upward.
        // Later opens keep the place the user left the window in.
        if opening && previousWindowFrame == nil { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Where the window was when it was last closed, so a later open puts
    /// it back there instead of centering again. Nil before the first close.
    private var previousWindowFrame: NSRect?

    /// A titled, closable window that can be neither resized nor
    /// miniaturized. Kept alive across closes (`isReleasedWhenClosed`
    /// false) so the next `show` reuses it; `show` centers it once its
    /// content is in.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + 2 * Self.margin, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "About KeyGrid"
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// Keeps `previousApp` pointing at the app the user most recently
    /// worked in while About is open. Every process but KeyGrid's own
    /// counts: KeyGrid itself is activated by `show` and by a click on
    /// the window, and is never where the user wants to land.
    private func startNotingActivations() {
        let own = ProcessInfo.processInfo.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier != own else { return }
            self.previousApp = activated
        }
    }

    /// Gives focus back to the app the user was in (`previousApp`) and
    /// remembers the window's place. Activating the other app is deferred
    /// by one turn of the run loop so the window is gone before it comes
    /// forward; otherwise macOS may keep KeyGrid active with no window.
    func windowWillClose(_ notification: Notification) {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        previousWindowFrame = window?.frame
        let previous = previousApp
        previousApp = nil
        DispatchQueue.main.async { _ = previous?.activate() }
    }

    /// Builds the column of labels. Every label wraps at `contentWidth`
    /// and is selectable, so the version or the path can be copied.
    private static func makeContent(accessibilityGranted: Bool) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: iconSide).isActive = true
        icon.heightAnchor.constraint(equalToConstant: iconSide).isActive = true
        stack.addArrangedSubview(icon)
        stack.setCustomSpacing(12, after: icon)

        let info = Bundle.main.infoDictionary ?? [:]
        let title = label(About.name, font: .boldSystemFont(ofSize: 20))
        stack.addArrangedSubview(title)
        let version = label("Version " + About.versionText(short: info["CFBundleShortVersionString"] as? String,
                                                           build: info["CFBundleVersion"] as? String),
                            color: .secondaryLabelColor)
        stack.addArrangedSubview(version)
        stack.setCustomSpacing(12, after: version)

        let description = label(About.description)
        stack.addArrangedSubview(description)
        stack.setCustomSpacing(12, after: description)

        stack.addArrangedSubview(label("What this app never does", font: .boldSystemFont(ofSize: NSFont.systemFontSize)))
        var lastPromise: NSView?
        for promise in About.promises {
            let line = label("•  " + promise)
            stack.addArrangedSubview(line)
            lastPromise = line
        }
        if let lastPromise { stack.setCustomSpacing(12, after: lastPromise) }

        // The home folder as `~`, as the README writes the path.
        let path = (ConfigStore.file.path as NSString).abbreviatingWithTildeInPath
        stack.addArrangedSubview(label("Config file: \(path)"))
        stack.addArrangedSubview(label("Accessibility permission: \(accessibilityGranted ? "granted" : "not granted")"))
        let signature = label(About.signatureText(identity: signingIdentity()))
        stack.addArrangedSubview(signature)
        stack.setCustomSpacing(12, after: signature)

        stack.addArrangedSubview(linkLabel(About.repository))
        if let copyright = info["NSHumanReadableCopyright"] as? String, !copyright.isEmpty {
            stack.addArrangedSubview(label(copyright, font: .systemFont(ofSize: NSFont.smallSystemFontSize), color: .secondaryLabelColor))
        }
        return stack
    }

    /// A wrapping, selectable, non-editable text field.
    private static func label(_ text: String,
                              font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
                              color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.isSelectable = true
        field.preferredMaxLayoutWidth = contentWidth
        return field
    }

    /// A label whose whole text is a link. AppKit opens a link in a
    /// selectable text field in the default browser on click, provided the
    /// field allows editing text attributes; no code of ours runs and
    /// nothing is fetched by the app.
    private static func linkLabel(_ urlText: String) -> NSTextField {
        let field = label(urlText)
        field.allowsEditingTextAttributes = true
        // `About.repository` is a literal https URL, so the parse cannot fail.
        let url = URL(string: urlText)!
        field.attributedStringValue = NSAttributedString(string: urlText, attributes: [
            .link: url,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
        return field
    }

    /// The subject of the certificate the running bundle was signed with
    /// (its name as Keychain Access shows it), or nil when the signature carries no certificate,
    /// which is what an ad-hoc signature (`codesign --sign -`, the
    /// Makefile's default) looks like, or when the signature cannot be
    /// read at all. Asks the Security framework about the running code
    /// itself: `SecCodeCopySelf` names the process, `SecCodeCopyStaticCode`
    /// its bundle on disk, and `SecCodeCopySigningInformation` with
    /// `kSecCSSigningInformation` returns the signature's certificates,
    /// leaf first. No permission is needed and nothing leaves the machine.
    static func signingIdentity() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [AnyObject],
              let leaf = certificates.first,
              CFGetTypeID(leaf) == SecCertificateGetTypeID() else { return nil }
        return SecCertificateCopySubjectSummary(leaf as! SecCertificate) as String?
    }
}
