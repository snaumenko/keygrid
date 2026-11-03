import AppKit
import ApplicationServices
import os
import KeyGridCore

/// Moves the focused window. For a window action it finds the window of
/// the app in front, works out its new frame with `Geometry` (a placement
/// from the display, or from the next display when the window already is
/// the half asked for, or, for `full` on a window that already fills its
/// display, the frame remembered before the fill; a display jump from
/// the window's place as fractions of its display, reapplied on the
/// previous or next one; `center` from the window's own size and the
/// display's center; a sweep or a move from the window's current frame
/// and the display's grid; a move at the display's edge from the next
/// display's grid), and sets it through the Accessibility API. For
/// the grid overlay it does the two
/// halves separately: `capture()` reads the focused window when the grid
/// hotkey is pressed, and `place(_:at:label:)` writes the frame the user
/// selected once the overlay closes. For the border drawn after a Dock
/// switch, `focusedWindowFrame(of:)` reads the frame of a named app's
/// focused window and converts it, so `WindowHighlight` can be handed an
/// AppKit frame and never touches the Accessibility API.
///
/// This is the one place in the program where frames cross between
/// AppKit coordinates and the Accessibility API's (see "Coordinate
/// systems" in `docs/ARCHITECTURE.md`), and the only caller of
/// `AXCoordinates`. Every press reads the displays and the window afresh;
/// the one thing kept between presses is `previousFrames`, the frames
/// windows had before `full` filled their display, so a second ⌃⌥⏎ can
/// put them back. It does not register hotkeys (`HotkeyCenter`), does
/// not decide which action a key means (`Config`), does no frame
/// arithmetic of its own (`Geometry`), and draws nothing (`GridOverlay`).
/// "How a window action works" and "How the grid overlay works" in
/// `docs/ARCHITECTURE.md` tell the whole path from key press to moved
/// window.
///
/// Every failure is logged with the action's config label and a reason a
/// person can act on, and the window is left alone. Nothing is shown on
/// screen for a failed press; the log is the record (the menu's error
/// line is for the config file and shortcut registration, not for single
/// presses).
final class WindowMover {
    /// Why an action could not be carried out. Worded for the log, naming
    /// the app where that tells the user something ("Finder has no focused
    /// window" explains a press that did nothing after clicking the desktop).
    enum Failure: Error, CustomStringConvertible {
        case noDisplays
        case noFrontmostApplication
        /// `AXError.apiDisabled`: the Accessibility permission is missing.
        case accessibilityDenied
        /// The app in front has no focused window (`AXError.noValue` on
        /// `kAXFocusedWindowAttribute`, or a value that is not a window).
        case noFocusedWindow(app: String)
        /// The focused window did not give its position or size. `status`
        /// is the API's answer: `.noValue` means the attribute exists but
        /// has nothing right now, `.failure` is either a system error or a
        /// value of the wrong type (see `AXUIElement.position`).
        case noFrame(app: String, attribute: String, status: AXError)
        /// Any other `AXError` while asking the app for its focused window.
        case accessibility(app: String, status: AXError)
        /// A sweep that could not change the frame: the window is already
        /// one grid column or row wide against that edge of the display.
        case nothingToSweep(WindowAction)
        /// A move whose window is at the display's edge on that side, or a
        /// half placement whose window already is that half, with no
        /// display beyond it.
        case noDisplayBeyond(WindowAction, Direction)
        /// `previousDisplay` or `nextDisplay` with a single display attached.
        case onlyOneDisplay
        /// `full` on a window that already fills its display, with no
        /// earlier frame remembered to go back to: the app was started
        /// after the fill, the window was filled some other way (by hand or
        /// with the grid overlay), or 32 newer fills pushed its frame out
        /// of `previousFrames`.
        case alreadyFull

        var description: String {
            switch self {
            case .noDisplays:
                return "no display is attached"
            case .noFrontmostApplication:
                return "no app is in front"
            case .accessibilityDenied:
                return "Accessibility permission is not granted; use Grant Accessibility… in the menu"
            case .noFocusedWindow(let app):
                return "\(app) has no focused window"
            case .noFrame(let app, let attribute, let status):
                return "the focused window of \(app) did not give its \(attribute) (\(status.name))"
            case .accessibility(let app, let status):
                return "\(app) could not be asked for its window (\(status.name))"
            case .nothingToSweep(let action):
                return "\(action.rawValue) can go no further; the window is already one grid cell wide against that edge"
            case .onlyOneDisplay:
                return "only one display is attached"
            case .alreadyFull:
                return "the window already fills its display and no earlier frame is remembered"
            case .noDisplayBeyond(let action, let direction):
                let side: String
                switch direction {
                case .left: side = "left"
                case .right: side = "right"
                case .up: side = "top"
                case .down: side = "bottom"
                }
                return "\(action.rawValue) can go no further; the window is at the \(side) edge of its display and no display is there"
            }
        }
    }

    /// A focused window read at one moment, kept so it can be moved later.
    /// The grid overlay captures the window when its hotkey is pressed and
    /// places it when the user releases the mouse, perhaps seconds later and
    /// after focus has moved; this is what carries the window across that
    /// gap. `app` is the app's name for the log, `pid` is the process the
    /// window belongs to (the overlay cancels when another process is
    /// activated), and `element` is the Accessibility handle used to write
    /// the frame. It holds no frame: the frame is read when it is needed.
    struct CapturedWindow {
        let app: String
        let pid: pid_t
        let element: AXUIElement
    }

    private static let log = Logger(subsystem: "com.keygrid.app", category: "window")

    /// The frames windows had before and after `full` filled their
    /// display, keyed by the window's Accessibility element; two elements
    /// are equal when they name the same element of the same process, so
    /// the window read on two presses is the same key. In memory only and
    /// empty at launch, so after a start ⌃⌥⏎ can only fill, never put a
    /// window back. `FrameMemory` keeps the newest 32.
    private var previousFrames = FrameMemory<AXUIElement, FilledWindow>()

    /// The grid size the sweep and move actions step by, `Config.Grid.size`:
    /// cells along the shorter edge of a display. `AppController` sets it
    /// on every config reload. A config without a `grid` section has no
    /// grid to show, but the sweeps and moves still need a step, so the
    /// default size stays in force then.
    var gridSize = Config.defaultGridSize

    /// Moves and resizes the focused window for `action`. When nothing can
    /// be done the reason goes to the log and the window stays put.
    func perform(_ action: WindowAction) {
        do {
            try performOrThrow(action)
        } catch {
            Self.log.error("window.\(action.rawValue, privacy: .public) ignored: \(String(describing: error), privacy: .public)")
        }
    }

    private func performOrThrow(_ action: WindowAction) throws {
        let screens = NSScreen.screens
        guard let primary = screens.first else { throw Failure.noDisplays }
        let primaryHeight = primary.frame.height

        let window = try capture()
        let current = AXCoordinates.fromAX(try Self.frame(of: window.element, app: window.app), primaryHeight: primaryHeight)

        let label = "window.\(action.rawValue)"
        let screenIndex: Int
        if let found = Self.indexOfScreen(containing: current, in: screens) {
            screenIndex = found
        } else {
            // Possible for a moment after a display is unplugged, or if the
            // app reported a nonsense frame; said out loud rather than tiled
            // onto the first display in silence.
            Self.log.notice("\(label, privacy: .public): the window at \(Self.describe(current), privacy: .public) overlaps no display; using the first one")
            screenIndex = 0
        }

        let visible = Rect(screens[screenIndex].visibleFrame)
        // The grid is the one the overlay would draw on this display:
        // `gridSize` cells along its shorter edge, the longer edge derived.
        let layout = Geometry.gridLayout(for: visible, size: gridSize)
        let target: Rect
        if let direction = action.sweepDirection {
            target = Geometry.sweep(current, direction, columns: layout.columns, rows: layout.rows, in: visible)
            // `sameFrame` rather than `==`: a no-op sweep rebuilds the width
            // as (x + w) - x, which can be a hair off w for a fractional frame.
            if Geometry.sameFrame(target, current) { throw Failure.nothingToSweep(action) }
        } else if let direction = action.moveDirection {
            if let stepped = Geometry.move(current, direction, columns: layout.columns, rows: layout.rows, in: visible) {
                target = stepped
            } else {
                // At the display's edge: onto the display beyond it, keeping
                // the window's size in grid cells on that display's own grid.
                let next = try Self.adjacentScreen(beyond: screenIndex, direction, spanning: current, in: screens, for: action)
                let destination = Rect(screens[next].visibleFrame)
                target = Geometry.carry(current, direction,
                                        from: visible, layout,
                                        to: destination, Geometry.gridLayout(for: destination, size: gridSize))
            }
        } else if let step = action.displayStep {
            // The displays in left-to-right order, wrapping at both ends.
            guard screens.count > 1 else { throw Failure.onlyOneDisplay }
            let order = Geometry.displayOrder(screens.map { Rect($0.frame) })
            // `displayOrder` returns every index once, so `screenIndex` is
            // always found; the `?? 0` only satisfies the optional.
            let position = order.firstIndex(of: screenIndex) ?? 0
            let next = order[(position + step + order.count) % order.count]
            target = Geometry.frameMoving(current, from: visible, to: Rect(screens[next].visibleFrame))
        } else if action == .center {
            target = Geometry.centered(current, in: visible)
        } else if action == .full, let fullFrame = Geometry.frame(for: .full, in: visible) {
            // A toggle. "Full" is the display's full frame, or the frame the
            // window actually took at its last fill (a Terminal window keeps
            // a few points short of full and would otherwise never count).
            // Full: go back to the remembered frame, exactly as it was, even
            // if the displays have been rearranged since; or do nothing when
            // nothing is remembered. Not full: remember where the window is
            // and what it became, then fill.
            let remembered = previousFrames.peek(for: window.element)
            let isFull = Geometry.sameFrame(current, fullFrame)
                || remembered.map { Geometry.sameFrame(current, $0.after) } == true
            if isFull {
                guard let previous = previousFrames.take(for: window.element) else {
                    throw Failure.alreadyFull
                }
                target = previous.before
            } else {
                let after = place(window, at: fullFrame, label: label) ?? fullFrame
                previousFrames.remember(FilledWindow(before: current, after: after), for: window.element)
                return
            }
        } else if let placed = Geometry.frame(for: action, in: visible) {
            if let direction = action.carryDirection, let half = action.oppositeHalf, Geometry.sameFrame(current, placed) {
                // The window already is the half `action` names: the press puts it on the
                // display on that side instead, as that display's near half
                // (a true half there, whatever its grid), or fails like a move
                // at the edge with no display beyond.
                let next = try Self.adjacentScreen(beyond: screenIndex, direction, spanning: current, in: screens, for: action)
                guard let landed = Geometry.frame(for: half, in: Rect(screens[next].visibleFrame)) else {
                    preconditionFailure("\(half.rawValue) is a placement and always has a frame")
                }
                target = landed
            } else {
                target = placed
            }
        } else {
            // Every `WindowAction` is a sweep, a move, a display jump, `center`,
            // `full`, or a placement that `Geometry.frame(for:in:)` gives a
            // frame; the branches above cover those six kinds (`sweepDirection`,
            // `moveDirection`, `displayStep` and `frame(for:in:)` each switch
            // over the whole enum, and `frame` returns nil only for sweeps,
            // moves, display jumps and `center`), so this branch is unreachable.
            preconditionFailure("\(action.rawValue) is neither a sweep, a move, a display jump, center, nor a placement")
        }

        place(window, at: target, label: label)
    }

    /// The index in `screens` of the display beyond `direction`'s edge of
    /// the display at `sourceIndex`, or `Failure.noDisplayBeyond` for
    /// `action` when no display is there. Adjacency is decided on whole
    /// display frames (`NSScreen.frame`), which macOS lays out edge to
    /// edge, and on `window`'s span along the shared edge
    /// (`Geometry.adjacentDisplay`).
    private static func adjacentScreen(beyond sourceIndex: Int, _ direction: Direction, spanning window: Rect,
                                       in screens: [NSScreen], for action: WindowAction) throws -> Int {
        let frames = screens.map { Rect($0.frame) }
        guard let next = Geometry.adjacentDisplay(to: frames[sourceIndex], direction, spanning: window, among: frames) else {
            throw Failure.noDisplayBeyond(action, direction)
        }
        return next
    }

    /// The focused window of the app in front, ready to be moved now or
    /// later with `place(_:at:label:)`. Throws a `Failure` when there is no
    /// app in front, it has no focused window, or the Accessibility
    /// permission is missing.
    func capture() throws -> CapturedWindow {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw Failure.noFrontmostApplication
        }
        return try Self.capture(app: app)
    }

    /// The frame of `app`'s focused window, in AppKit coordinates. `app`
    /// is named rather than taken from the front because the caller,
    /// `AppController` after a Dock switch, has just asked that app
    /// forward and reads its window the moment macOS reports it active,
    /// when `NSWorkspace.frontmostApplication` may still name the app
    /// that was in front before. Throws a `Failure` when the app has no
    /// focused window, when it did not give the window's position or size,
    /// or when the Accessibility permission is missing.
    func focusedWindowFrame(of app: NSRunningApplication) throws -> Rect {
        guard let primary = NSScreen.screens.first else { throw Failure.noDisplays }
        let window = try Self.capture(app: app)
        return AXCoordinates.fromAX(try Self.frame(of: window.element, app: window.app), primaryHeight: primary.frame.height)
    }

    /// The focused window of `app`, with the app's name for the log.
    /// `capture()` calls it with the app in front and
    /// `focusedWindowFrame(of:)` with the app a Dock shortcut named.
    private static func capture(app: NSRunningApplication) throws -> CapturedWindow {
        let name = app.localizedName ?? app.bundleIdentifier ?? "the app"
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let read = element.copyAttribute(kAXFocusedWindowAttribute)
        switch read.status {
        case .success: break
        case .apiDisabled: throw Failure.accessibilityDenied
        // The app has no focused window; the API reports that as "no value".
        case .noValue: throw Failure.noFocusedWindow(app: name)
        default: throw Failure.accessibility(app: name, status: read.status)
        }
        guard let window = read.value, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            throw Failure.noFocusedWindow(app: name)
        }
        return CapturedWindow(app: name, pid: app.processIdentifier, element: window as! AXUIElement)
    }

    /// Moves `window` to `target`, an AppKit frame, and reads the frame
    /// back. `label` names the caller in the log: `window.leftHalf` for a
    /// window action, `grid` for the overlay. The write is logged if the
    /// window refuses it, and the result is logged at notice level if the
    /// window kept a different frame, so "nothing happened" has a record in
    /// `log show`. Nothing is thrown: by the time this runs the user has
    /// acted, and the honest answer is what the window did. That answer is
    /// also returned, the frame read back after the write, or nil when it
    /// could not be read; the `full` toggle keeps it to recognise the
    /// window as filled next time.
    @discardableResult
    func place(_ window: CapturedWindow, at target: Rect, label: String) -> Rect? {
        guard let primary = NSScreen.screens.first else {
            Self.log.error("\(label, privacy: .public) ignored: \(String(describing: Failure.noDisplays), privacy: .public)")
            return nil
        }
        let primaryHeight = primary.frame.height
        Self.setFrame(of: window.element, to: AXCoordinates.toAX(target, primaryHeight: primaryHeight), label: label)

        // The API's "accepted" is not "done": a window with a minimum size or
        // a fixed aspect keeps what it can. Read back and say so, at a level
        // `log show` keeps, so "nothing happened" has a record. The writes
        // are already done here, so a failed read-back (the window closed in
        // between) is reported as that, not as the action being ignored.
        let result: Rect
        do {
            result = AXCoordinates.fromAX(try Self.frame(of: window.element, app: window.app), primaryHeight: primaryHeight)
        } catch {
            Self.log.notice("\(label, privacy: .public): frame written, but it could not be read back: \(String(describing: error), privacy: .public)")
            return nil
        }
        if !Geometry.sameFrame(result, target) {
            Self.log.notice("\(label, privacy: .public): \(window.app, privacy: .public) kept \(Self.describe(result), privacy: .public) instead of \(Self.describe(target), privacy: .public); the window kept a different frame (usually a minimum size or fixed aspect ratio)")
        } else {
            Self.log.info("\(label, privacy: .public): placed \(window.app, privacy: .public) at \(Self.describe(result), privacy: .public)")
        }
        return result
    }

    /// The window's frame in Accessibility coordinates, or a `Failure`
    /// naming which attribute the app would not give and why.
    private static func frame(of window: AXUIElement, app: String) throws -> Rect {
        let position = window.position
        guard let point = position.value else {
            throw failure(reading: "position", status: position.status, app: app)
        }
        let size = window.size
        guard let extent = size.value else {
            throw failure(reading: "size", status: size.status, app: app)
        }
        return Rect(x: point.x, y: point.y, width: extent.width, height: extent.height)
    }

    private static func failure(reading attribute: String, status: AXError, app: String) -> Failure {
        status == .apiDisabled ? .accessibilityDenied : .noFrame(app: app, attribute: attribute, status: status)
    }

    /// `x,y w×h` with whole numbers, for the log.
    private static func describe(_ rect: Rect) -> String {
        "\(Int(rect.x.rounded())),\(Int(rect.y.rounded())) \(Int(rect.width.rounded()))×\(Int(rect.height.rounded()))"
    }

    /// The index in `screens` of the display showing most of `frame`
    /// (largest overlap by area), in AppKit coordinates. Nil when the frame
    /// overlaps no display at all.
    private static func indexOfScreen(containing frame: Rect, in screens: [NSScreen]) -> Int? {
        var best: Int?
        var bestArea = 0.0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.frame.intersection(CGRect(frame))
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                best = index
                bestArea = area
            }
        }
        return best
    }

    /// Writes a frame, in Accessibility coordinates, as size, then
    /// position, then size again. Position first can be refused when the
    /// current size does not fit the destination display; size first can
    /// be clamped by the display the window is still on. Writing the size
    /// on both sides of the move gets both right in one pass. A window that
    /// will not take the exact size keeps what it accepts; there is no
    /// retry. A refused write is logged once with the steps that failed;
    /// the caller reads the frame back to learn what the window did.
    private static func setFrame(of window: AXUIElement, to frame: Rect, label: String) {
        let size = CGSize(width: frame.width, height: frame.height)
        let position = CGPoint(x: frame.x, y: frame.y)
        let statuses = [window.setSize(size), window.setPosition(position), window.setSize(size)]
        let failed = zip(["size", "position", "size"], statuses)
            .filter { $0.1 != .success }
            .map { "\($0.0): \($0.1.name)" }
        if !failed.isEmpty {
            log.error("\(label, privacy: .public): the window refused the write (\(failed.joined(separator: "; "), privacy: .public))")
        }
    }
}

extension Rect {
    /// A `Rect` from AppKit's `CGRect`, which `NSScreen` reports. Same
    /// numbers, no conversion: both are AppKit coordinates.
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}

extension CGRect {
    /// The reverse of `Rect.init(_:)`: same numbers, AppKit coordinates.
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
