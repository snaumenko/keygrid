import AppKit
import KeyGridCore

/// Shows the placement grid over one display and reports the rectangle
/// the user selects.
///
/// `show(on:onSelect:onCancel:)` dims the display, draws the configured
/// grid over its visible frame, and waits. A drag from one cell to another
/// (or a click on one cell) ends in `onSelect` with the selected frame in
/// AppKit coordinates; Escape, the activation of another app, or a change
/// of display arrangement ends in `onCancel` with a sentence saying which,
/// for the log. `cancel()` from the caller ends in neither. Either way the
/// panel is gone before the closure runs, and each closure runs at most
/// once per `show`. `AppController` decides when to show the overlay and what to do
/// with the frame; this type never reads the config, never captures or
/// moves a window, and never registers a hotkey. "How the grid overlay
/// works" in `docs/ARCHITECTURE.md` tells the whole path from key press to
/// placed window.
///
/// The panel is non-activating: showing it does not make KeyGrid the
/// active app, so the app whose window is about to be moved stays in
/// front and an activation of any other app is a real switch, which
/// cancels. It is still made the key window, because only the key window
/// receives key presses, and Escape is one.
final class GridOverlay {
    /// The grid size, `Config.Grid.size`: cells along the shorter edge of
    /// the display. `AppController` sets it on every config reload whose
    /// config has a `grid` section; without one there is no grid hotkey, so
    /// no grid is shown. `show(on:)` turns it into a column and row count
    /// for the display it is shown on, so a portrait display gets the same
    /// grid turned on its side. The value here only exists so the property
    /// has a type, and is never drawn.
    var size = 6

    /// True from `show` until the selection, cancel, or app switch that
    /// ends it. `AppController` reads it to make a second hotkey press
    /// cancel instead of opening a second grid.
    var isShowing: Bool { panel != nil }

    private var panel: GridPanel?
    /// Notification registrations that live only while the grid shows, each
    /// paired with the center it was added to so it can be removed from
    /// that center: another app being activated (the workspace center) and
    /// the displays being rearranged (the default center).
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// Shows the grid over `screen`. `allowedPID` is
    /// `WindowMover.CapturedWindow.pid`, the process whose activation does
    /// not cancel: macOS may report it as activated while the panel appears.
    func show(on screen: NSScreen, allowedPID: pid_t, onSelect: @escaping (Rect) -> Void, onCancel: @escaping (_ reason: String) -> Void) {
        cancel()
        // Read once, so the grid drawn and the frame handed back use the same
        // origin even if the displays are rearranged in between (which also
        // cancels the grid, below).
        let origin = screen.frame.origin

        let panel = GridPanel(contentRect: screen.frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        // `.screenSaver` sits above full-screen apps and the menu bar, so
        // the grid covers whatever the user is looking at.
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        // Follow the user to every Space, sit beside full-screen windows
        // instead of being hidden by them, and stay put when Spaces move.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // The grid is laid over the visible frame, the same frame the window
        // actions use, so a half dragged on the grid is the frame `leftHalf`
        // or `rightHalf` places, and a sweep or a move lands on the lines drawn here.
        // The dim covers the whole display, menu
        // bar and Dock included. The visible frame is converted from screen
        // coordinates to the view's by subtracting the display's origin,
        // because the panel's frame is the display's frame.
        let view = GridView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.grid = Rect(screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y))
        let layout = Geometry.gridLayout(for: view.grid, size: size)
        view.columns = layout.columns
        view.rows = layout.rows
        view.onSelect = { [weak self] frameInView in
            guard let self else { return }
            // Back to screen coordinates for the caller.
            let frame = Rect(x: frameInView.x + origin.x,
                             y: frameInView.y + origin.y,
                             width: frameInView.width,
                             height: frameInView.height)
            self.dismiss()
            onSelect(frame)
        }
        view.onCancel = { [weak self] in
            self?.dismiss()
            onCancel("Escape was pressed")
        }
        panel.contentView = view
        self.panel = panel

        // Any app other than the captured window's coming to the front means
        // the user has moved on. macOS may report the captured app itself as
        // activated while the panel appears; that is not a switch.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, let activated, activated.processIdentifier != allowedPID else { return }
            self.dismiss()
            onCancel("\(activated.localizedName ?? "another app") came to the front")
        }))
        // A display unplugged or rearranged moves the origin the grid was
        // drawn against; the drawn cells would no longer be where the window
        // would land.
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isShowing else { return }
            self.dismiss()
            onCancel("the display arrangement changed")
        }))

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        // Start the hover highlight from where the mouse already is, rather
        // than waiting for it to move.
        view.updateHover(screenPoint: NSEvent.mouseLocation, screenOrigin: origin)
    }

    /// Hides the grid without placing anything. Does nothing when no grid
    /// is showing. The `onCancel` passed to `show` is not called: the
    /// caller asked for this and already knows.
    func cancel() {
        dismiss()
    }

    private func dismiss() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        // `dismiss` runs from inside the panel's own mouseUp or keyDown. Freeing
        // the window while it is still handling the event is something AppKit
        // tolerates but does not promise; holding it until the run loop turns
        // once costs nothing.
        DispatchQueue.main.async { _ = panel }
    }
}

/// The overlay's window. An `NSPanel` subclass exists only to say yes to
/// `canBecomeKey`: a borderless window refuses to be key by default, and
/// the grid must be key to receive Escape. With `.nonactivatingPanel` in
/// the style mask, becoming key does not activate the app.
private final class GridPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Draws the dim, the grid lines, the hovered cell, and the selection, and
/// turns mouse and key events into a selected frame or a cancel.
///
/// Every coordinate here is in the view's own space, where the display's
/// bottom-left corner is (0, 0); `GridOverlay` converts to and from screen
/// coordinates, except in `updateHover(screenPoint:screenOrigin:)`, which
/// takes a screen point so the hover can be seeded from
/// `NSEvent.mouseLocation` before the first mouse move. Which cell a point is in and which frame a pair of cells
/// spans are `Geometry.gridCell` and `Geometry.gridFrame`, which also put
/// row 0 at the top; the view does no cell arithmetic of its own.
private final class GridView: NSView {
    /// The frame the grid is laid over (the display's visible frame, in
    /// view coordinates) and its size in cells. Set before the view is shown.
    var grid = Rect(x: 0, y: 0, width: 1, height: 1)
    var columns = 1
    var rows = 1

    /// Called with the selected frame, in view coordinates. Cleared before
    /// it runs so a second mouse up cannot call it again.
    var onSelect: ((Rect) -> Void)?
    /// Called when the user presses Escape. Cleared before it runs, like
    /// `onSelect`.
    var onCancel: (() -> Void)?

    /// The cell the mouse went down on; nil before the mouse goes down and
    /// again after it comes up.
    private var anchor: GridCell?
    /// The cell under the mouse now: the other corner of the selection
    /// while dragging, the hover highlight before that.
    private var hovered: GridCell?

    private static let dim = NSColor.black.withAlphaComponent(0.35)
    private static let line = NSColor.white.withAlphaComponent(0.25)
    private static let hover = NSColor.white.withAlphaComponent(0.15)
    private static let selectionFill = NSColor.controlAccentColor.withAlphaComponent(0.35)
    private static let selectionBorder = NSColor.controlAccentColor

    override var acceptsFirstResponder: Bool { true }

    /// KeyGrid is never the active app while the grid shows, and AppKit
    /// normally withholds the first click, and all mouse-moved events, from
    /// windows of an inactive app. Saying yes here delivers the first click;
    /// the tracking area below delivers the moves.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// The cell under a point given in screen coordinates. Used by
    /// `GridOverlay` to seed the hover before the first mouse move.
    func updateHover(screenPoint: NSPoint, screenOrigin: NSPoint) {
        hovered = cell(at: NSPoint(x: screenPoint.x - screenOrigin.x, y: screenPoint.y - screenOrigin.y))
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = cell(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let cell = cell(at: convert(event.locationInWindow, from: nil))
        anchor = cell
        hovered = cell
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        hovered = cell(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // A press that started before the grid appeared has no anchor; the
        // release then selects nothing.
        guard let anchor else { return }
        let end = cell(at: convert(event.locationInWindow, from: nil))
        self.anchor = nil
        let select = onSelect
        onSelect = nil
        select?(Geometry.gridFrame(from: anchor, to: end, columns: columns, rows: rows, in: grid))
    }

    override func keyDown(with event: NSEvent) {
        // Escape is handled here rather than through AppKit's
        // `cancelOperation`, which only arrives when `super.keyDown` runs the
        // key through the responder chain. Every other key is swallowed on
        // purpose: the grid is modal while it shows, and `super.keyDown`
        // would beep for a key the view does not handle.
        if event.keyCode == 53 {   // kVK_Escape in Carbon's Events.h
            let cancel = onCancel
            onCancel = nil
            cancel?()
        }
    }

    private func cell(at point: NSPoint) -> GridCell {
        Geometry.gridCell(at: Point(x: point.x, y: point.y), columns: columns, rows: rows, in: grid)
    }

    private func frame(of cell: GridCell) -> NSRect {
        CGRect(Geometry.gridFrame(from: cell, to: cell, columns: columns, rows: rows, in: grid))
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.dim.setFill()
        bounds.fill()

        // Grid lines: every cell's frame stroked at one point, inset by half
        // a point so the stroke sits on the pixel row rather than between two.
        Self.line.setStroke()
        for column in 0..<columns {
            for row in 0..<rows {
                let path = NSBezierPath(rect: frame(of: GridCell(column: column, row: row)).insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()
            }
        }

        if let anchor, let hovered {
            let selection = CGRect(Geometry.gridFrame(from: anchor, to: hovered, columns: columns, rows: rows, in: grid))
            Self.selectionFill.setFill()
            selection.fill()
            Self.selectionBorder.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        } else if let hovered {
            Self.hover.setFill()
            frame(of: hovered).fill()
        }
    }
}
