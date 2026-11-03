/// Converts a window frame between the two coordinate systems macOS uses
/// for the same screen: AppKit's, with the origin at the bottom-left of
/// the primary display and y growing upward, and the Accessibility API's,
/// with the origin at the top-left of the primary display and y growing
/// downward.
///
/// Every `Rect` in `Geometry` is AppKit. The Accessibility API, which the
/// app uses to read and set a window's position (`kAXPositionAttribute`),
/// speaks the other system. This type is the arithmetic between them;
/// the section "Coordinate systems" in `docs/ARCHITECTURE.md` describes
/// both systems and where the conversion sits. `WindowMover` in the app
/// is the only intended caller: it converts a frame once when reading it
/// from the Accessibility API, once when writing it back, and once more
/// when reading the result back. Nothing here talks to a display or a
/// window.
///
/// Only y changes. The two systems share x, width, height, and the unit
/// (points). The flip is around the primary display's full frame height:
/// a top edge `maxY` points above the AppKit origin is `primaryHeight -
/// maxY` points below the Accessibility origin. The primary display is
/// the one AppKit lists first in `NSScreen.screens` (not `NSScreen.main`,
/// which is the display with keyboard focus); its full height is the
/// pivot, not its visible height, because the menu bar moves neither
/// origin. The pivot is a parameter because `KeyGridCore` imports no
/// framework and so cannot read `NSScreen.screens[0].frame.height`
/// itself; the app passes it in.
///
/// Nothing is rounded: a fractional frame reported by the Accessibility
/// API on a scaled display keeps its fractional x, width, and height, and
/// its y is a plain subtraction. `Geometry` is where frames are rounded
/// to whole points.
public enum AXCoordinates {
    /// An AppKit frame as the Accessibility API expects it: same x and
    /// size, y measured downward from the top of the primary display to
    /// the window's top edge.
    public static func toAX(_ appKit: Rect, primaryHeight: Double) -> Rect {
        Rect(x: appKit.x, y: primaryHeight - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    /// A frame reported by the Accessibility API as AppKit sees it: same x
    /// and size, y measured upward from the bottom of the primary display
    /// to the window's bottom edge.
    ///
    /// The formula is the one in `toAX(_:primaryHeight:)`; flipping around
    /// the pivot is its own inverse. The second name exists so a call site
    /// says which direction it converts.
    public static func fromAX(_ ax: Rect, primaryHeight: Double) -> Rect {
        Rect(x: ax.x, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }
}
