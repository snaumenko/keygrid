import AppKit
import ServiceManagement
import os
import KeyGridCore

/// The object that owns the running app. `main.swift` creates one and
/// makes it the `NSApplicationDelegate`; macOS then calls
/// `applicationDidFinishLaunching` once the app is ready.
///
/// `AppController` creates the long-lived pieces and connects them: the
/// `ConfigStore` that reads the settings file, the `HotkeyCenter` that
/// registers shortcuts, the `DockSwitcher` the Dock shortcuts drive, the
/// `WindowMover` the window shortcuts drive, the `GridOverlay` the grid
/// shortcut shows, the `WindowHighlight` drawn after a Dock shortcut,
/// the `AboutWindow` the menu opens, and the `StatusMenu`. It also
/// answers the menu's Launch at Login item by registering or
/// unregistering the app as a login item with `SMAppService`. The
/// behaviour lives in those pieces, not here. When the config changes, `applyConfig` tears down
/// every shortcut and registers the new set.
///
/// Two shortcuts join pieces here rather than in one of them. `toggleGrid`
/// captures the focused window with `WindowMover`, shows `GridOverlay` on
/// the display under the mouse, and places the window where the user
/// selected; the grid size from the config goes to both `GridOverlay` (to
/// draw) and `WindowMover` (the sweep and move actions step by one grid
/// cell). A Dock shortcut asks `DockSwitcher` to bring an app forward,
/// then `highlightFocusedWindow(of:label:)` waits until that app reports
/// itself active, reads its focused window's frame with `WindowMover`,
/// and shows `WindowHighlight` around it, when `Config.dockHighlight` is
/// on.
///
/// It also asks for the Accessibility permission at launch and re-checks
/// it every two seconds, because macOS posts no documented notification
/// when the user grants or revokes it.
final class AppController: NSObject, NSApplicationDelegate {
    private let hotkeys = HotkeyCenter()
    private let dock = DockSwitcher()
    private let windows = WindowMover()
    private let grid = GridOverlay()
    private let about = AboutWindow()
    private let highlight = WindowHighlight()
    private var config: ConfigStore?
    private var menu: StatusMenu?
    private var trustTimer: Timer?
    /// `Config.dockHighlight` of the last applied config: whether a Dock
    /// shortcut is followed by a border around the window it brought
    /// forward.
    private var highlightAfterDockSwitch = true
    /// The wait for one Dock-switched app to come to the front: the timer
    /// that asks the app every `activationPollInterval` whether it is
    /// active, and gives up after `activationTimeout`. Nil when no wait is
    /// on. A new Dock press or a config reload ends the wait.
    private var activationWait: Timer?
    /// Bumped by every `cancelActivationWait`, which every Dock press and
    /// every config reload calls first. The closures a press leaves behind
    /// (the poll timer, the retry of a window read) carry the count they
    /// saw when the press started and do nothing when it has moved on, so
    /// a late one from an earlier press cannot end or draw over the press
    /// that followed it.
    private var activationWaitCount = 0

    /// The three inputs of the menu's `StatusState`, kept here so `refreshMenu`
    /// can recompute it whenever one changes: whether the Accessibility
    /// permission is granted, the config file's last error (nil when it
    /// loaded), and every shortcut that could not be registered on the last
    /// `applyConfig`, one line each.
    private var accessibilityGranted = false
    private var configError: String?
    private var hotkeyFailures: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = Accessibility.isTrusted(prompt: true)
        HotkeyCenter.log.notice("Accessibility permission at launch: \(trusted ? "granted" : "missing", privacy: .public)")

        accessibilityGranted = trusted
        let menu = StatusMenu(state: .resolve(accessibilityGranted: trusted, configError: nil, hotkeyFailures: []),
                              errorLine: nil,
                              launchAtLogin: Self.loginItemState())
        menu.onGrantAccessibility = { Accessibility.openSystemSettings() }
        menu.onLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }
        menu.onMenuWillOpen = { [weak self] in self?.refreshMenu() }
        menu.onOpenConfig = {
            if !NSWorkspace.shared.open(ConfigStore.file) {
                HotkeyCenter.log.error("could not open \(ConfigStore.file.path, privacy: .public) in an editor")
            }
        }
        menu.onAbout = { [weak self] in
            guard let self else { return }
            self.about.show(accessibilityGranted: self.accessibilityGranted)
        }
        menu.onQuit = { NSApp.terminate(nil) }
        self.menu = menu

        let store = ConfigStore()
        store.onChange = { [weak self] config in self?.applyConfig(config) }
        store.onStatus = { [weak self] status in
            if status == nil { HotkeyCenter.log.info("config status: ok") }
            self?.configError = status
            self?.refreshMenu()
        }
        config = store
        menu.onReloadConfig = { store.reload() }
        configError = store.lastError
        applyConfig(store.current)
        store.startWatching()

        // .common mode keeps the timer firing while the status menu is open,
        // so the icon and first item update under the user's eyes.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = Accessibility.isTrusted(prompt: false)
            if trusted != self.accessibilityGranted {
                if trusted {
                    HotkeyCenter.log.notice("Accessibility permission granted")
                } else {
                    HotkeyCenter.log.error("Accessibility permission revoked; Dock and window shortcuts do nothing until it is granted again")
                }
                self.accessibilityGranted = trusted
                self.refreshMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    /// Recomputes the menu's state and error line from the three inputs,
    /// reads the login item's state from macOS, and hands them to the menu.
    /// Cheap; called whenever an input changes and every time the menu is
    /// about to open, so what the menu shows is what is true at that
    /// moment (the login item can be changed in System Settings while
    /// KeyGrid runs). `ConfigStore` starts a load error with the config
    /// file's path, which the log needs and the menu does not (there is
    /// only one file), so the menu gets the message without it.
    /// Returns the login item state it read, so a caller that has just
    /// changed the item can act on the new state without a second read.
    @discardableResult
    private func refreshMenu() -> LoginItemState {
        let pathPrefix = ConfigStore.file.path + ": "
        let shownError = configError.map { $0.hasPrefix(pathPrefix) ? String($0.dropFirst(pathPrefix.count)) : $0 }
        let state = StatusState.resolve(accessibilityGranted: accessibilityGranted, configError: shownError, hotkeyFailures: hotkeyFailures)
        let line = StatusState.errorLine(configError: shownError, hotkeyFailures: hotkeyFailures)
        let login = Self.loginItemState()
        menu?.update(state: state, errorLine: line, launchAtLogin: login)
        return login
    }

    private static let loginLog = Logger(subsystem: "com.keygrid.app", category: "login")

    /// The login item's state as macOS reports it for this app bundle,
    /// mapped onto `LoginItemState` for the menu. `SMAppService.mainApp` is
    /// Apple's handle on "this app as a login item"; `status` asks the
    /// system, not a cached value. "How launch at login works" in
    /// `docs/ARCHITECTURE.md` tells the whole path.
    private static func loginItemState() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered:   return .off
        case .enabled:         return .on
        case .requiresApproval: return .needsApproval
        // `notFound` is what macOS reports for an app that has never
        // registered, not only for a missing bundle; mapping it to
        // unavailable would grey the item out before its first use. If the
        // bundle really is missing, `register()` throws and the error is
        // logged.
        case .notFound:        return .off
        @unknown default:      return .unavailable
        }
    }

    /// The Launch at Login item's action. Off registers the login item, on
    /// unregisters it, and a registration macOS is still waiting for the
    /// person to allow opens System Settings at the Login Items pane. The
    /// menu is refreshed afterwards with whatever macOS now reports, which
    /// after a failure is the truth too. The login item points at the
    /// bundle that is running now; registering one that is in neither
    /// `/Applications` nor `~/Applications` (`dist/KeyGrid.app` from
    /// `make run`, which the next build deletes and recreates) is allowed
    /// but logged, because the next login opens whatever is at that path
    /// by then.
    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        switch Self.loginItemState() {
        case .off:
            let path = Bundle.main.bundleURL.path
            let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
            if !path.hasPrefix("/Applications/") && !path.hasPrefix(userApplications) {
                Self.loginLog.notice("launch at login registers \(path, privacy: .public); a bundle outside /Applications is replaced by the next build, so `make install` first and turn the item on from there")
            }
            do {
                try service.register()
                Self.loginLog.notice("launch at login turned on")
            } catch {
                Self.loginLog.error("launch at login could not be turned on: \(error.localizedDescription, privacy: .public)")
            }
            // macOS 13 and later may register the item but hold it until the
            // person allows it in System Settings; the person just asked, so
            // open the pane where the allowing happens. `refreshMenu` reads
            // the state once and shows it; its answer is reused here.
            if refreshMenu() == .needsApproval {
                Self.loginLog.notice("launch at login needs approval in System Settings → General → Login Items & Extensions")
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        case .on:
            do {
                try service.unregister()
                Self.loginLog.notice("launch at login turned off")
            } catch {
                Self.loginLog.error("launch at login could not be turned off: \(error.localizedDescription, privacy: .public)")
            }
        case .needsApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .unavailable:
            // The item has no action in this state, so a click cannot
            // arrive; nothing to do if one somehow does.
            break
        }
        refreshMenu()
    }

    /// Replaces every registered shortcut with the ones in `config`.
    /// Failures are logged and collected into `hotkeyFailures`, which the
    /// menu's error line shows; the shortcuts that did register stay
    /// registered.
    private func applyConfig(_ config: Config) {
        hotkeys.unregisterAll()
        // A grid open during a reload would place with the old size or stay
        // open under a hotkey that no longer exists.
        grid.cancel()
        // A border still waited for belongs to a press under the old
        // config; the new one may have turned borders off.
        cancelActivationWait()
        highlightAfterDockSwitch = config.dockHighlight
        if let section = config.grid {
            grid.size = section.size
            windows.gridSize = section.size
        } else {
            windows.gridSize = Config.defaultGridSize
        }
        var failures: [String] = []
        for (position, hotkey) in config.dockHotkeys {
            do {
                try hotkeys.register(hotkey) { [weak self] in
                    guard let self else { return }
                    let app = self.dock.activate(position: position)
                    if self.highlightAfterDockSwitch, let app {
                        self.highlightFocusedWindow(of: app, label: "dock.\(position)")
                    }
                }
                HotkeyCenter.log.info("registered dock.\(position) as \(hotkey, privacy: .public)")
            } catch {
                let message = "dock.\(position): \(error)"
                failures.append(message)
                HotkeyCenter.log.error("\(message, privacy: .public)")
            }
        }
        for action in WindowAction.allCases {
            guard let hotkey = config.windowBindings[action] else { continue }
            let label = "window.\(action.rawValue)"
            do {
                try hotkeys.register(hotkey) { [weak self] in
                    self?.windows.perform(action)
                }
                HotkeyCenter.log.info("registered \(label, privacy: .public) as \(hotkey, privacy: .public)")
            } catch {
                let message = "\(label): \(error)"
                failures.append(message)
                HotkeyCenter.log.error("\(message, privacy: .public)")
            }
        }
        if let hotkey = config.grid?.hotkey {
            do {
                try hotkeys.register(hotkey) { [weak self] in
                    self?.toggleGrid()
                }
                HotkeyCenter.log.info("registered grid.hotkey as \(hotkey, privacy: .public)")
            } catch {
                let message = "grid.hotkey: \(error)"
                failures.append(message)
                HotkeyCenter.log.error("\(message, privacy: .public)")
            }
        }
        hotkeyFailures = failures
        refreshMenu()
        // Logged at .notice because macOS keeps .notice lines on disk, where
        // `log show` finds them, while the .info "registered" lines above
        // are dropped unless a log stream is attached. This one line answers
        // "what did the last reload bind?". The unbound list is how a
        // misspelled action name in the file becomes visible: the decoder
        // ignores an unknown key, so the action simply does not appear as
        // bound.
        let unbound = WindowAction.allCases.filter { config.windowBindings[$0] == nil }.map(\.rawValue)
        let unboundText = unbound.isEmpty ? "none" : unbound.joined(separator: ", ")
        // Three grid states read differently in the file, so they are named
        // rather than counted: no `grid` section, a section with a null or
        // missing hotkey, or a shortcut.
        let gridText: String
        switch config.grid {
        case nil: gridText = "off"
        case .some(let grid): gridText = grid.hotkey.map { "\($0)" } ?? "unbound"
        }
        HotkeyCenter.log.notice("applied config: \(config.dockHotkeys.count) dock and \(config.windowBindings.count) window shortcuts, dock highlight \(config.dockHighlight ? "on" : "off", privacy: .public), grid \(gridText, privacy: .public), \(failures.count) failed; unbound window actions: \(unboundText, privacy: .public)")
    }

    private static let dockLog = Logger(subsystem: "com.keygrid.app", category: "dock")

    /// How long a Dock-switched app may take to come to the front before
    /// the border is given up. The Dock's press is answered by the app on
    /// its own time; a busy app can take most of a second. After 1.5
    /// seconds the user has long since seen the switch happen (or not) and
    /// a border would only confuse.
    private static let activationTimeout: TimeInterval = 1.5

    /// How often the wait asks the app whether it is active yet. 50
    /// milliseconds is quicker than the eye notices a border's delay, and
    /// one Accessibility read per tick for at most `activationTimeout` is
    /// nothing.
    private static let activationPollInterval: TimeInterval = 0.05

    /// How long to wait before reading the focused window a second time
    /// when the first read found none. The Dock's press can still be
    /// making the window: a click on the active app with no windows opens
    /// one (Finder after a click on the desktop), and a click on an app
    /// with every window minimized brings one back. One retry is the whole
    /// allowance.
    private static let focusedWindowRetryDelay: TimeInterval = 0.3

    /// Shows a border around the focused window of `app`, which
    /// `DockSwitcher.activate` has just asked forward under the shortcut
    /// `label` (`dock.3`). The window is read once `app` reports itself
    /// active: at once when it already is (the shortcut named the active
    /// app, whose windows the Dock brings forward), otherwise on the first
    /// of the checks every `activationPollInterval` that finds it so, for
    /// up to `activationTimeout`. Every reason a border does not appear is
    /// logged under `label` at notice level.
    ///
    /// The app is asked through Accessibility (`kAXFrontmostAttribute` on
    /// its application element) rather than told by
    /// `NSWorkspace.didActivateApplicationNotification`: on the owner's
    /// machine the notification did not reach KeyGrid within the timeout
    /// after the first press for an app in the background, so the first
    /// press drew nothing while later presses, for the app now in front,
    /// did. `NSWorkspace.frontmostApplication` is updated by the same
    /// notification and so is no better. The app's own answer does not
    /// depend on KeyGrid's run loop being told anything.
    private func highlightFocusedWindow(of app: NSRunningApplication, label: String) {
        cancelActivationWait()
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if element.isFrontmost == true {
            showHighlight(of: app, label: label)
            return
        }
        let wait = activationWaitCount
        let deadline = Date().addingTimeInterval(Self.activationTimeout)
        let poll = Timer(timeInterval: Self.activationPollInterval, repeats: true) { [weak self] _ in
            guard let self, self.activationWaitCount == wait else { return }
            if element.isFrontmost == true {
                self.cancelActivationWait()
                self.showHighlight(of: app, label: label)
            } else if Date() >= deadline {
                self.cancelActivationWait()
                let name = app.localizedName ?? app.bundleIdentifier ?? "the app"
                Self.dockLog.notice("\(label, privacy: .public): no border; \(name, privacy: .public) did not come to the front within \(Self.activationTimeout, format: .fixed(precision: 1)) seconds")
            }
        }
        // .common mode, like the permission timer: the checks keep running
        // even while the status menu is open.
        RunLoop.main.add(poll, forMode: .common)
        activationWait = poll
    }

    /// Ends the wait started by `highlightFocusedWindow(of:label:)`, if one
    /// is on, and moves `activationWaitCount` past it so its closures do
    /// nothing if they still fire.
    private func cancelActivationWait() {
        activationWaitCount += 1
        activationWait?.invalidate()
        activationWait = nil
    }

    /// Reads `app`'s focused window and shows the border around it. When
    /// the app has no focused window yet and `retry` is true, reads once
    /// more after `focusedWindowRetryDelay`, unless another Dock press or a
    /// config reload has come in between. Otherwise logs under `label` why
    /// there is no border: the app has no focused window (every window
    /// minimized or closed), it did not give the window's frame, or the
    /// Accessibility permission went missing in between.
    private func showHighlight(of app: NSRunningApplication, label: String, retry: Bool = true) {
        do {
            highlight.show(around: try windows.focusedWindowFrame(of: app))
        } catch WindowMover.Failure.noFocusedWindow(let name) where retry {
            let wait = activationWaitCount
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusedWindowRetryDelay) { [weak self] in
                guard let self, self.activationWaitCount == wait else { return }
                self.showHighlight(of: app, label: label, retry: false)
            }
            Self.dockLog.info("\(label, privacy: .public): \(name, privacy: .public) has no focused window yet; reading again in \(Self.focusedWindowRetryDelay) seconds")
        } catch {
            Self.dockLog.notice("\(label, privacy: .public): no border; \(String(describing: error), privacy: .public)")
        }
    }

    private static let gridLog = Logger(subsystem: "com.keygrid.app", category: "grid")

    /// The grid hotkey's handler. A press while the grid is showing cancels
    /// it; otherwise the focused window is captured first, so the result
    /// does not depend on what showing a panel does to focus, and the grid
    /// appears on the display under the mouse.
    private func toggleGrid() {
        if grid.isShowing {
            Self.gridLog.notice("grid cancelled: the grid hotkey was pressed again")
            grid.cancel()
            return
        }
        let window: WindowMover.CapturedWindow
        do {
            window = try windows.capture()
        } catch {
            Self.gridLog.error("grid.hotkey ignored: \(String(describing: error), privacy: .public)")
            return
        }
        let mouse = NSEvent.mouseLocation
        // `NSMouseInRect` with `flipped: false` counts the top and right edges
        // as inside, which `NSRect.contains` does not; the mouse can rest on
        // a display's top row of points.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.screens.first else {
            Self.gridLog.error("grid.hotkey ignored: no display is attached")
            return
        }
        Self.gridLog.info("grid shown for \(window.app, privacy: .public) on the display at \(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y))")
        grid.show(on: screen, allowedPID: window.pid, onSelect: { [weak self] frame in
            self?.windows.place(window, at: frame, label: "grid")
        }, onCancel: { reason in
            Self.gridLog.notice("grid cancelled: \(reason, privacy: .public)")
        })
    }
}
