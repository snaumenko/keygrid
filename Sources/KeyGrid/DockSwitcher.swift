import AppKit
import ApplicationServices
import os

/// Reads the application icons in the Dock, in the order they are shown,
/// and brings the one at a given position forward.
///
/// The Dock is an ordinary app (`com.apple.dock`) and, like every app,
/// exposes its user interface through the Accessibility API as a tree of
/// elements. Its icons are children of an `AXList` element; application
/// icons have the subrole `AXApplicationDockItem`, while separators,
/// folders, minimized windows and the Trash have other subroles. Reading
/// that tree needs the Accessibility permission (see `Accessibility`).
///
/// "Position" here means what the user sees, counted from the left:
/// Finder is 1 because macOS always pins it first, and running apps that
/// are not pinned, and "recent applications", count in the places the
/// Dock shows them. The tree is read on every call rather than cached, so
/// the numbering follows the Dock as apps open and quit.
///
/// Activating an item means performing its `AXPress` action, which the
/// Dock treats like a plain click on the icon: a running app comes
/// forward, a stopped one launches. `activate(position:)` reports which
/// running app it asked forward so that `AppController` can draw a border
/// around that app's focused window; `DockSwitcher` itself reads no
/// window and draws nothing. `docs/ARCHITECTURE.md`, "How a Dock
/// shortcut works", tells the whole path from key press to app.
final class DockSwitcher {
    /// One application icon in the Dock.
    struct Item {
        /// Position counted from the left, starting at 1.
        let position: Int
        /// The app's name as the Dock shows it.
        let title: String
        /// The app bundle, when the Dock reports one.
        let url: URL?
        /// The Dock's own element for the icon, used to press it.
        fileprivate let element: AXUIElement
    }

    /// Why the Dock could not be read. Each case is worded for the log,
    /// which is where a person looks when a shortcut did nothing.
    enum ReadError: Error, CustomStringConvertible {
        case dockNotRunning
        /// `AXError.apiDisabled`: the Accessibility permission is missing.
        case accessibilityDenied
        /// Any other `AXError` from the Dock's top-level element.
        case accessibility(AXError)
        /// The Dock answered but its tree had no `AXList` of icons.
        case noIconList

        var description: String {
            switch self {
            case .dockNotRunning:
                return "the Dock is not running"
            case .accessibilityDenied:
                return "Accessibility permission is not granted; use Grant Accessibility… in the menu"
            case .accessibility(let error):
                return "the Dock could not be read (\(error.name))"
            case .noIconList:
                return "the Dock's accessibility tree has no list of icons"
            }
        }
    }

    private static let log = Logger(subsystem: "com.keygrid.app", category: "dock")

    /// The application icons in the Dock, left to right. Throws a
    /// `ReadError` saying why when the Dock cannot be read.
    static func applications() throws -> [Item] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw ReadError.dockNotRunning
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let read = app.copyAttribute(kAXChildrenAttribute)
        switch read.status {
        case .success: break
        case .apiDisabled: throw ReadError.accessibilityDenied
        default: throw ReadError.accessibility(read.status)
        }
        let children = read.value as? [AXUIElement] ?? []
        let lists = children.filter { $0.role == kAXListRole }
        guard !lists.isEmpty else { throw ReadError.noIconList }

        var items: [Item] = []
        for list in lists {
            for element in list.children ?? [] where element.subrole == "AXApplicationDockItem" {
                let url = element.url
                if url == nil {
                    // The Dock always reports a bundle URL for an app icon;
                    // a missing one would make the fallback in activate() useless.
                    log.error("Dock item \(element.title ?? "?", privacy: .public) reports no URL")
                }
                items.append(Item(position: items.count + 1,
                                  title: element.title ?? url?.deletingPathExtension().lastPathComponent ?? "untitled",
                                  url: url,
                                  element: element))
            }
        }
        return items
    }

    /// Brings the app at `position` (1-based, as the user sees it) forward,
    /// launching it if it is not running. When nothing can be done, the
    /// reason goes to the log: the Dock could not be read, or the position
    /// is past the last icon.
    ///
    /// Returns the app that was asked forward when it was already running,
    /// so the caller can highlight its focused window once it is in front.
    /// Returns nil when the shortcut did nothing, and also when the app was
    /// stopped and is now launching: its first window appears seconds
    /// later with the app's own launch animation, and a border would have
    /// to wait an unknown time to find it.
    func activate(position: Int) -> NSRunningApplication? {
        let items: [Item]
        do {
            items = try Self.applications()
        } catch {
            Self.log.error("dock.\(position) ignored: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard items.indices.contains(position - 1) else {
            Self.log.notice("dock.\(position) ignored: the Dock shows only \(items.count) app icons")
            return nil
        }
        let item = items[position - 1]
        // Looked up before the press, while "running" still means "was
        // running before the shortcut": after the press a stopped app is
        // launching and would be found too.
        let running = item.url.flatMap(Self.runningApplication(at:))
        let status = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        if status == .success {
            Self.log.info("\(running == nil ? "launching" : "activated", privacy: .public) \(item.title, privacy: .public) at position \(position)")
            return running
        }
        // The press failed. Open the bundle directly, which also activates
        // a running app or launches a stopped one.
        guard let url = item.url else {
            Self.log.error("could not press \(item.title, privacy: .public) (\(status.name, privacy: .public)) and it has no URL")
            return nil
        }
        Self.log.error("press failed for \(item.title, privacy: .public) (\(status.name, privacy: .public)); opening \(url.path, privacy: .public) instead")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Self.log.error("could not open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return running
    }

    /// The running app with the bundle identifier of the bundle at `url`,
    /// the URL the Dock reports for an icon, or nil when the bundle's
    /// `Info.plist` cannot be read or no such process exists. Matching by
    /// identifier rather than by path is what the Dock does when it decides
    /// whether a click activates or launches: a copy of the app running
    /// from another folder, or another version, is the app the press
    /// brings forward. `Bundle(url:)` reads one `Info.plist` from disk, the
    /// only file read on a Dock press.
    private static func runningApplication(at url: URL) -> NSRunningApplication? {
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
    }
}
