import AppKit
import KeyGridCore

/// A border around one window's frame that fades away, so the eye finds
/// the window a Dock shortcut has just brought forward.
///
/// `show(around:)` takes a frame in AppKit screen coordinates, lays a
/// borderless panel over it, strokes a rounded border along the frame's
/// edge, holds it for `holdSeconds`, fades the panel out over
/// `fadeSeconds`, and removes it. A second `show` while a border is on
/// screen replaces it; `hide()` removes the border at once. The panel
/// ignores the mouse and is never key or activating, so it changes
/// neither focus nor what a click lands on.
///
/// This type reads no window, no config and no display. `AppController`
/// decides when a border is shown, `Config.dockHighlight` whether it is
/// shown at all, and `WindowMover.focusedWindowFrame(of:)` supplies the
/// frame; "How a Dock shortcut works" in `docs/ARCHITECTURE.md` tells the
/// path from key press to border. The frame may hang off a display's
/// edge, as the window itself may; the border is clipped where the
/// display ends, like the window.
final class WindowHighlight {
    /// The stroke, in points, centred on the window's edge: half inside
    /// the window, half outside. Three points reads at a glance on a
    /// Retina display without hiding the window's own edge, and the half
    /// that lies inside stays visible for a window flush against a
    /// display's edge.
    static let borderWidth: CGFloat = 3
    /// The corner radius, in points, so the border follows the window's
    /// corner instead of cutting across it. AppKit offers no public way to
    /// read a window's own corner radius, so this is a constant per macOS
    /// generation. macOS 11 to 15 round windows by about 10 points. macOS
    /// 26 rounds them much more, about 16 points for a plain window and
    /// about 26 for one with a toolbar (Finder, Safari); 20 sits close to
    /// both, and the owner picked it on screen.
    static let cornerRadius: CGFloat =
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) ? 20 : 10
    /// How long the border stays at full opacity before the fade begins.
    /// Long enough to be seen, short enough that a second shortcut right
    /// after does not find the first border still bright.
    static let holdSeconds: TimeInterval = 0.25
    /// How long the fade from full opacity to transparent takes.
    static let fadeSeconds: TimeInterval = 0.4

    /// The border on screen, or nil. The fade scheduled by `show` checks
    /// that the panel it was made for is still the panel held here before
    /// it runs, so a `show` or `hide` in between needs no other bookkeeping.
    private var panel: NSPanel?

    /// Shows a border along the edge of `frame`, a window frame in AppKit
    /// screen coordinates, and starts its fade. A border already on screen
    /// is removed first.
    func show(around frame: Rect) {
        hide()
        // The panel is the window's frame grown by the stroke width on
        // every side, so the outer half of the stroke has room to be drawn.
        let panelFrame = CGRect(frame).insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth)
        let panel = NSPanel(contentRect: panelFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        // `.screenSaver` sits above full-screen apps and the menu bar, the
        // level the grid overlay uses too, so the border shows wherever the
        // window is.
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        // Follow the user to every Space, sit beside full-screen windows
        // instead of being hidden by them, and stay put when Spaces move.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = HighlightView(frame: NSRect(origin: .zero, size: panelFrame.size))
        // `orderFrontRegardless` shows the panel although KeyGrid is not
        // the active app, which it never is; `orderFront` may decline then.
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds) { [weak self] in
            // A `show` or `hide` during the hold has replaced or removed the
            // panel; the fade belongs to the panel that is gone.
            guard let self, self.panel === panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fadeSeconds
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.panel === panel else { return }
                self.hide()
            })
        }
    }

    /// Removes the border now, fading or not. Does nothing when no border
    /// is on screen.
    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
    }
}

/// Strokes the border. The view fills its panel, whose frame is the
/// window's frame grown by `WindowHighlight.borderWidth` on every side, so
/// the rectangle inset by that width is the window's frame and the stroke
/// centred on it straddles the window's edge. Draws nothing else: no fill,
/// no shadow, no text.
private final class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let edge = bounds.insetBy(dx: WindowHighlight.borderWidth, dy: WindowHighlight.borderWidth)
        let path = NSBezierPath(roundedRect: edge,
                                xRadius: WindowHighlight.cornerRadius,
                                yRadius: WindowHighlight.cornerRadius)
        path.lineWidth = WindowHighlight.borderWidth
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
