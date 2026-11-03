/// What the menu bar icon and the menu should show: everything fine, the
/// Accessibility permission missing, or a problem with the config file or
/// the shortcuts. A pure decision from three inputs; it draws nothing and
/// knows nothing about menus, which is `StatusMenu`'s business in the app.
public enum StatusState: Equatable, Sendable {
    /// Permission granted, config loaded, every shortcut registered.
    case ok
    /// The Accessibility permission is missing; without it the Dock and
    /// window shortcuts do nothing.
    case needsAccessibility
    /// The config file could not be loaded, or some shortcuts could not be
    /// registered. Carries the full text, one problem per line.
    case problem(String)

    /// Decides the state. A missing permission wins over a problem, since
    /// nothing else matters until it is granted. A config error wins over
    /// failed shortcuts, since while the file is broken the shortcuts are
    /// the previous settings' and the file is what to fix first. Blank
    /// lines in `hotkeyFailures` are ignored.
    public static func resolve(accessibilityGranted: Bool, configError: String?, hotkeyFailures: [String]) -> StatusState {
        if !accessibilityGranted { return .needsAccessibility }
        let configLines = lines(of: configError)
        if !configLines.isEmpty { return .problem(configLines.joined(separator: "\n")) }
        let failures = hotkeyFailures.flatMap { lines(of: $0) }
        if !failures.isEmpty { return .problem(failures.joined(separator: "\n")) }
        return .ok
    }

    /// The one line the menu shows for a problem, or nil when there is
    /// none. The config error comes first, as in `resolve`. Only the first
    /// line of the problem text is shown, followed by " (+N more)" when
    /// there are further lines, so a long list never makes a huge menu
    /// item; the whole text is in the log. A config error is normally one
    /// line, so the count mostly applies to failed shortcuts, one line
    /// each. The prefix names the kind: "Config error: " or "Shortcut
    /// failed: ". The problem text is cut to `maxShown` characters with an
    /// ellipsis, because a menu item does not wrap and one long line would
    /// make the whole menu that wide.
    public static func errorLine(configError: String?, hotkeyFailures: [String]) -> String? {
        let configLines = lines(of: configError)
        if !configLines.isEmpty { return line(prefix: "Config error: ", from: configLines) }
        let failures = hotkeyFailures.flatMap { lines(of: $0) }
        return failures.isEmpty ? nil : line(prefix: "Shortcut failed: ", from: failures)
    }

    /// The most characters of problem text the error line shows, prefix and
    /// count not included: about the width of a wide menu at the system
    /// font, enough for every message the config and hotkey checks produce
    /// once the file path is dropped.
    public static let maxShown = 90

    /// The non-blank lines of `text`, trimmed; empty for nil. `resolve` and
    /// `errorLine` both read their inputs through this, so the two never
    /// disagree about whether there is a problem.
    private static func lines(of text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingWhitespace() }
            .filter { !$0.isEmpty }
    }

    private static func line(prefix: String, from lines: [String]) -> String? {
        guard let first = lines.first else { return nil }
        let shown = first.count > maxShown ? String(first.prefix(maxShown - 1)) + "…" : first
        let more = lines.count - 1
        return prefix + shown + (more > 0 ? " (+\(more) more)" : "")
    }
}
