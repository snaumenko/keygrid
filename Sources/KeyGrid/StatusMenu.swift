import AppKit
import KeyGridCore

/// The icon in the menu bar and the menu under it.
///
/// This is the app's only visible surface. The icon doubles as a health
/// light, driven by a `StatusState`: KeyGrid's nine-dot board when all is
/// well; the board with a badge in its bottom-right corner when the
/// Accessibility permission is missing, since without it the Dock
/// shortcuts do nothing; the board with a filled disc with an exclamation mark cut out of it,
/// in the same corner, when the config file or some shortcuts have a
/// problem. A problem also shows as a disabled line in the menu naming
/// it, in the permission-missing state too, so granting the permission
/// does not hide a broken file. The three images are PNG pairs in `Resources/`
/// (`MenuBarIcon`, `MenuBarIconBadge`, `MenuBarIconProblem`, each with an
/// `@2x` partner), copied into the bundle by the Makefile. The menu offers
/// the few actions a person needs: grant the permission, open or reload
/// the config file, turn launch at login on or off, open the About
/// window, quit.
///
/// `StatusMenu` decides nothing: `StatusState` (in `KeyGridCore`) picks
/// the state and the error text, `LoginItemState` (also in
/// `KeyGridCore`) the words and checkmark of the Launch at Login item,
/// `AppController` calls `update`, and the menu only draws. It exposes one
/// closure per action, plus `onMenuWillOpen` so `AppController` can
/// refresh the state the moment the menu drops down, and `AppController`
/// fills them in.
final class StatusMenu: NSObject, NSMenuDelegate {

    var onGrantAccessibility: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onLaunchAtLogin: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    /// Called just before the menu is shown, so the state it shows (the
    /// permission, the error line, the login item) is read now rather
    /// than when something last changed.
    var onMenuWillOpen: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let accessibilityItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()
    private let icon = StatusMenu.templateImage(named: "MenuBarIcon")
    private let badgedIcon = StatusMenu.templateImage(named: "MenuBarIconBadge")
    private let problemIcon = StatusMenu.templateImage(named: "MenuBarIconProblem")

    init(state: StatusState, errorLine: String?, launchAtLogin: LoginItemState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        buildMenu()
        update(state: state, errorLine: errorLine, launchAtLogin: launchAtLogin)
    }

    /// Creates the fixed menu items once. `update` only changes their
    /// text and the icon.
    private func buildMenu() {
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        errorItem.isEnabled = false             // a line of status, not a command
        errorItem.isHidden = true
        menu.addItem(errorItem)
        menu.addItem(makeItem("Open Config File", #selector(openConfig)))
        menu.addItem(makeItem("Reload Config", #selector(reloadConfig)))
        launchAtLoginItem.target = self      // the action is set by `update`, per state
        menu.addItem(launchAtLoginItem)
        menu.addItem(makeItem("About KeyGrid", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit KeyGrid", #selector(quit), key: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Puts the icon, the first menu item, the error line and the Launch
    /// at Login item in line with `state`, `errorLine` and `launchAtLogin`.
    /// Call it whenever one may have changed; it is cheap and does nothing
    /// visible when they have not.
    func update(state: StatusState, errorLine: String?, launchAtLogin: LoginItemState) {
        switch state {
        case .ok:                 statusItem.button?.image = icon
        case .needsAccessibility: statusItem.button?.image = badgedIcon
        case .problem:            statusItem.button?.image = problemIcon
        }
        if state == .needsAccessibility {
            accessibilityItem.title = "Grant Accessibility…"
            accessibilityItem.action = #selector(grantAccessibility)
        } else {
            accessibilityItem.title = "Accessibility: granted"
            accessibilityItem.action = nil          // a disabled line of status, not a command
        }
        errorItem.title = errorLine ?? ""
        errorItem.isHidden = errorLine == nil
        launchAtLoginItem.title = launchAtLogin.menuTitle
        launchAtLoginItem.state = launchAtLogin.isChecked ? .on : .off
        // The menu auto-enables its items (`NSMenu.autoenablesItems`, the
        // default): an item with an action is enabled and one without is
        // disabled, whatever `isEnabled` says. So, like `accessibilityItem`
        // above, the item is disabled by taking its action away.
        launchAtLoginItem.action = launchAtLogin.isEnabled ? #selector(toggleLaunchAtLogin) : nil
    }

    /// `NSMenuDelegate`: AppKit calls it before the menu is shown.
    func menuWillOpen(_ menu: NSMenu) { onMenuWillOpen?() }

    /// Loads `<name>.png` (and its `@2x` partner for Retina displays)
    /// from the app bundle's `Resources` folder as a template image:
    /// black on transparent, which macOS repaints in the menu bar's own
    /// colour, dark on a light bar and light on a dark bar. A missing
    /// file is a packaging mistake, so it stops the app with a message
    /// rather than showing an empty menu bar slot.
    private static func templateImage(named name: String) -> NSImage {
        guard let image = Bundle.main.image(forResource: name) else {
            fatalError("KeyGrid.app is missing Resources/\(name).png; rebuild with `make run`")
        }
        image.isTemplate = true
        image.accessibilityDescription = "KeyGrid"
        return image
    }

    @objc private func grantAccessibility() { onGrantAccessibility?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func reloadConfig() { onReloadConfig?() }
    @objc private func toggleLaunchAtLogin() { onLaunchAtLogin?() }
    @objc private func about() { onAbout?() }
    @objc private func quit() { onQuit?() }
}
