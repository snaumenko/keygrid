/// The frame math behind the window hotkeys: given a placement action
/// and a display's visible frame, the frame the focused window should
/// get. The sweep and move actions have their own arithmetic in
/// `EdgeGeometry.swift` and the grid overlay in `GridGeometry.swift`,
/// both as extensions of this type.
///
/// Everything here is arithmetic on `Rect` values. Nothing reads a
/// display, finds a window, or moves one; `WindowMover` in the app reads
/// the display and the window, calls these functions to get
/// the target frame, and applies it through the Accessibility API. The
/// "visible frame" of a display is the part not covered by the menu bar
/// and the Dock, which is what AppKit's `NSScreen.visibleFrame` reports;
/// every action places the window inside it, never under the menu bar.
///
/// Edges are rounded to whole points. Half of an odd width is not a whole
/// number, and a window frame with a half-point edge cannot align with the
/// display's pixel grid. Rounding each edge, rather than each size, means
/// two halves meet at the same point and together cover the display
/// exactly. Display frames from AppKit are whole points, so rounding
/// never moves a result outside the frame it was computed from; a
/// fractional window frame (which the Accessibility API can report on a
/// scaled display) comes back with whole-point edges, so its size may
/// change by up to one point.
public enum Geometry {
    /// The frame for a placement action on one display: the whole visible
    /// frame, its left or right half, or its middle with an equal gap of
    /// one sixth of the shorter edge on every side, each from `visible`
    /// alone. Returns `nil` for `center`, whose frame keeps the window's
    /// size (`centered(_:in:)`), for a sweep or move action, whose frame
    /// depends on where the window is now (`sweep(_:_:columns:rows:in:)`
    /// and `move(_:_:columns:rows:in:)`), and for `previousDisplay` and
    /// `nextDisplay`, whose frame is on another display
    /// (`frameMoving(_:from:to:)`).
    public static func frame(for action: WindowAction, in visible: Rect) -> Rect? {
        // Each placement as fractions of the visible frame, 0 to 1: where
        // the left edge sits (0 is the display's left side), how much of the
        // width to take, where the bottom edge sits (0 is the bottom), and
        // how much of the height to take.
        let fraction: (left: Double, width: Double, bottom: Double, height: Double)
        switch action {
        case .full:      fraction = (left: 0,   width: 1,   bottom: 0, height: 1)
        case .leftHalf:  fraction = (left: 0,   width: 0.5, bottom: 0, height: 1)
        case .rightHalf: fraction = (left: 0.5, width: 0.5, bottom: 0, height: 1)
        case .centerTwoThirds:
            // The same number of points of gap on all four sides: one sixth
            // of the shorter edge, so on a landscape display the window is
            // two thirds of the height and a little more of the width. The
            // owner asked for equal gaps over lining up with the grid's
            // columns (issue 56). The gap is rounded once, before it is
            // applied, so the four gaps are the same whole number; rounding
            // each edge instead would split a half-point gap 158 and 157.
            // The edges are whole points already (display frames are), so
            // `rounded` changes nothing here and only builds the Rect.
            let gap = (min(visible.width, visible.height) / 6).rounded()
            return rounded(minX: visible.minX + gap, maxX: visible.maxX - gap,
                           minY: visible.minY + gap, maxY: visible.maxY - gap)
        case .center, .sweepLeft, .sweepRight, .sweepUp, .sweepDown,
             .moveLeft, .moveRight, .moveUp, .moveDown,
             .previousDisplay, .nextDisplay: return nil
        }
        return rounded(
            minX: visible.x + visible.width * fraction.left,
            maxX: visible.x + visible.width * (fraction.left + fraction.width),
            minY: visible.y + visible.height * fraction.bottom,
            maxY: visible.y + visible.height * (fraction.bottom + fraction.height))
    }

    /// The frame for `center`: `window` with its size kept exactly and its
    /// center moved onto the center of `visible`. Only the origin is
    /// rounded to whole points, so an odd leftover point goes to one side;
    /// rounding both edges, as the placements do, could grow the window by
    /// a point when its edges straddle coordinate 0, since `rounded()`
    /// sends halves away from zero in both directions. A window larger
    /// than `visible` is centered all the same and overhangs equally on
    /// both sides; the window's size is the window's business.
    public static func centered(_ window: Rect, in visible: Rect) -> Rect {
        let left = visible.minX + (visible.width - window.width) / 2
        let bottom = visible.minY + (visible.height - window.height) / 2
        return Rect(x: left.rounded(), y: bottom.rounded(), width: window.width, height: window.height)
    }

    /// The indices of `frames` (display frames, `NSScreen.frame`) in the
    /// order a person reads them: left to right by left edge, and for the
    /// same left edge bottom to top by bottom edge. "Previous" and "next"
    /// display mean neighbours in this list, wrapping at both ends, so the
    /// order does not depend on how macOS happens to list the displays
    /// (primary first, the rest in no promised order). Stable: two displays
    /// with the same origin keep their input order.
    public static func displayOrder(_ frames: [Rect]) -> [Int] {
        frames.indices.sorted { a, b in
            if frames[a].minX != frames[b].minX { return frames[a].minX < frames[b].minX }
            if frames[a].minY != frames[b].minY { return frames[a].minY < frames[b].minY }
            return a < b
        }
    }

    /// The frame a window should get when it moves from the display whose
    /// visible frame is `source` to the one whose visible frame is
    /// `destination`. The window keeps its position and size as fractions
    /// of the source, so a left half stays a left half on a display of a
    /// different size or shape. Then it is clamped: a window larger than
    /// the destination shrinks to fit, and one hanging past an edge is
    /// shifted inside.
    ///
    /// When `source` and `destination` are the same frame the result is
    /// `window` unchanged, for a whole-point window that lies inside the
    /// frame (rounding is the identity there); one hanging past an edge is
    /// still shifted inside. A source with zero or negative width or height has
    /// no fractions; the window is then placed at the destination's origin
    /// with the destination's size instead of dividing by zero.
    public static func frameMoving(_ window: Rect, from source: Rect, to destination: Rect) -> Rect {
        guard source.width > 0 && source.height > 0 else {
            return rounded(minX: destination.minX, maxX: destination.maxX, minY: destination.minY, maxY: destination.maxY)
        }

        // The window's place on the source, as fractions 0 to 1, applied to
        // the destination.
        let scaled = Rect(
            x: destination.x + destination.width * ((window.x - source.x) / source.width),
            y: destination.y + destination.height * ((window.y - source.y) / source.height),
            width: destination.width * (window.width / source.width),
            height: destination.height * (window.height / source.height))

        // Clamp: shrink to the destination first, so that the shift that
        // follows always has room and can never turn the frame inside out.
        let width = min(scaled.width, destination.width)
        let height = min(scaled.height, destination.height)
        let x = min(max(scaled.x, destination.minX), destination.maxX - width)
        let y = min(max(scaled.y, destination.minY), destination.maxY - height)

        return rounded(minX: x, maxX: x + width, minY: y, maxY: y + height)
    }

    /// Builds a `Rect` from its four edges, each rounded to the nearest
    /// whole point with Swift's `Double.rounded()`, whose default mode is
    /// `.toNearestOrAwayFromZero`: a half point moves away from zero, so on
    /// a display of odd width the extra point goes to the left half when
    /// coordinates are positive and to the right half when they are
    /// negative. Rounding edges rather than sizes is what makes
    /// neighbouring placements share an edge exactly.
    private static func rounded(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Rect {
        let left = minX.rounded(), right = maxX.rounded()
        let bottom = minY.rounded(), top = maxY.rounded()
        return Rect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}
