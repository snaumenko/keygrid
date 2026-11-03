/// A rectangle in display coordinates: four numbers, in points.
///
/// This type exists because `KeyGridCore` imports no framework, so
/// Apple's `CGRect` is not available to the frame math in `Geometry`.
/// It follows the AppKit convention: `x` and `y` are the bottom-left
/// corner, measured from the bottom-left corner of the primary display,
/// and `y` grows upward. The app converts `CGRect` to `Rect` and back at
/// its edge, in `WindowMover`. A `Rect` holds the Accessibility
/// API's top-left-origin coordinates only as the result of
/// `AXCoordinates.toAX(_:primaryHeight:)` or the argument of
/// `AXCoordinates.fromAX(_:primaryHeight:)`, at the moment a frame crosses
/// the Accessibility boundary; every `Rect` that reaches `Geometry` is
/// AppKit. The section "Coordinate systems" in `docs/ARCHITECTURE.md`
/// describes both systems.
///
/// It is a plain value, built once and never changed, with no checks: a
/// negative width is representable and means nothing. No code is expected
/// to make one; `Geometry` returns rectangles whose edges are in order
/// whenever the rectangles it is given are.
public struct Rect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The left edge: `x` under the name AppKit uses, so it reads alongside `maxX`.
    public var minX: Double { x }
    /// The bottom edge: `y` under the name AppKit uses, so it reads alongside `maxY`.
    public var minY: Double { y }
    /// The right edge.
    public var maxX: Double { x + width }
    /// The top edge.
    public var maxY: Double { y + height }
}

/// A position in display coordinates: two numbers, in points.
///
/// `KeyGridCore` imports no framework, so `CGPoint` is not available to
/// the grid math in `Geometry`; `Point` stands in for it. It follows the
/// AppKit convention, measured from the bottom-left corner of the primary
/// display with `y` growing upward. `GridView` in
/// `Sources/KeyGrid/GridOverlay.swift` converts the `NSPoint` it reads
/// from AppKit to a `Point` before calling `Geometry`. It is a plain value with no checks and no arithmetic of its
/// own.
public struct Point: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
