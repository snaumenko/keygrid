/// The four directions a sweep or move hotkey pushes a window: towards
/// the left, right, top, or bottom of its display. Only a name; the
/// arithmetic is `Geometry.sweep` (one edge moves) and `Geometry.move`,
/// `Geometry.adjacentDisplay` and `Geometry.carry` (the whole window
/// moves, across displays at the edge).
public enum Direction: Sendable {
    case left, right, up, down
}

extension Geometry {
    /// Edges closer than this to a grid line, a display edge, or each
    /// other count as on it: one point. Window frames read through the
    /// Accessibility API can be a fraction off on a scaled display, and
    /// `Geometry` rounds every target to whole points. Every edge
    /// comparison in `Geometry` uses it.
    static let edgeTolerance = 1.0

    /// Whether two frames are the same frame for the program's purposes:
    /// every edge within `edgeTolerance`. `WindowMover` uses it to see
    /// whether a window took the frame it was given, whether a sweep did
    /// anything, whether a window already is the half a placement would
    /// make it, and whether a window already fills its display (the
    /// `full` toggle).
    public static func sameFrame(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.minX - b.minX) <= edgeTolerance && abs(a.maxX - b.maxX) <= edgeTolerance
            && abs(a.minY - b.minY) <= edgeTolerance && abs(a.maxY - b.maxY) <= edgeTolerance
    }

    /// The frame a window gets from one press of a sweep hotkey. The grid
    /// is `columns × rows` cells laid over `visible`, the display's visible
    /// frame, with the same edge rounding the grid overlay draws, so a
    /// sweep lands on the lines the overlay shows.
    ///
    /// A sweep works on one axis and leaves the other alone. Take `.left`;
    /// the other directions mirror it:
    ///
    /// - **Grow.** While the window's left edge is not at the display's
    ///   left edge, the left edge moves to the nearest grid line to its
    ///   left and the right edge stays. An edge already on a line moves
    ///   one whole column; an edge between two lines moves onto the line,
    ///   which is less than a column.
    /// - **Shrink.** Once the left edge is at the display's left edge
    ///   (within `edgeTolerance`), the right edge moves to the nearest
    ///   grid line to its left instead, but never past the first line in
    ///   from the display's edge: the window is never thinner than one
    ///   column. When even that is impossible the frame comes back
    ///   unchanged, and the caller can tell by comparing.
    ///
    /// A window hanging past the display's edge counts as at the edge, so
    /// the first press shrinks it rather than growing it into nothing. On
    /// a 12×6 grid, a window on the right half reaches full width after
    /// six `.left` presses; eleven more leave a one-column strip on the
    /// left. The edge that moved is a grid line, a whole point; the other
    /// three edges keep the window's own values.
    public static func sweep(_ window: Rect, _ direction: Direction, columns: Int, rows: Int, in visible: Rect) -> Rect {
        switch direction {
        case .left:
            let lines = edges(from: visible.minX, length: visible.width, count: columns)
            let (low, high) = sweepTowardsLow(low: window.minX, high: window.maxX, lines: lines)
            return Rect(x: low, y: window.y, width: high - low, height: window.height)
        case .right:
            let lines = edges(from: visible.minX, length: visible.width, count: columns)
            let (low, high) = sweepTowardsHigh(low: window.minX, high: window.maxX, lines: lines)
            return Rect(x: low, y: window.y, width: high - low, height: window.height)
        case .down:
            // Grid lines along y run upward here, from the bottom edge, so
            // `.down` is the low direction, like `.left` is on x.
            let lines = edges(from: visible.minY, length: visible.height, count: rows)
            let (low, high) = sweepTowardsLow(low: window.minY, high: window.maxY, lines: lines)
            return Rect(x: window.x, y: low, width: window.width, height: high - low)
        case .up:
            let lines = edges(from: visible.minY, length: visible.height, count: rows)
            let (low, high) = sweepTowardsHigh(low: window.minY, high: window.maxY, lines: lines)
            return Rect(x: window.x, y: low, width: window.width, height: high - low)
        }
    }

    /// One axis of a sweep towards the low end (`.left` or `.down`).
    /// `lines` ascend; `lines.first` is the display's edge on that side.
    /// Returns the window's new low and high coordinates on that axis.
    private static func sweepTowardsLow(low: Double, high: Double, lines: [Double]) -> (Double, Double) {
        let edge = lines[0]
        if low > edge + edgeTolerance {
            // Grow: the low edge steps to the nearest line below it.
            return (lineBelow(low, in: lines) ?? edge, high)
        }
        // Shrink: the high edge steps down, but stays at or above the first
        // line in from the display's edge so one column remains.
        guard lines.count > 1, let next = lineBelow(high, in: lines), next >= lines[1] else {
            return (low, high)
        }
        return (low, next)
    }

    /// One axis of a sweep towards the high end (`.right` or `.up`).
    /// `lines` ascend; `lines.last` is the display's edge on that side.
    private static func sweepTowardsHigh(low: Double, high: Double, lines: [Double]) -> (Double, Double) {
        let edge = lines[lines.count - 1]
        if high < edge - edgeTolerance {
            return (low, lineAbove(high, in: lines) ?? edge)
        }
        guard lines.count > 1, let next = lineAbove(low, in: lines), next <= lines[lines.count - 2] else {
            return (low, high)
        }
        return (next, high)
    }

    /// The largest line more than `edgeTolerance` below `value`, or nil
    /// when `value` is within `edgeTolerance` of, or below, the first line.
    private static func lineBelow(_ value: Double, in lines: [Double]) -> Double? {
        lines.last { $0 < value - edgeTolerance }
    }

    /// The smallest line more than `edgeTolerance` above `value`, or nil
    /// when `value` is within `edgeTolerance` of, or above, the last line.
    private static func lineAbove(_ value: Double, in lines: [Double]) -> Double? {
        lines.first { $0 > value + edgeTolerance }
    }
}

extension Geometry {
    /// The frame a window gets from one press of a move hotkey, or nil
    /// when the window is already at the display's edge on that side and
    /// the caller should look for another display there
    /// (`adjacentDisplay(to:_:spanning:among:)` and
    /// `carry(_:_:from:_:to:_:)`). The grid is `columns × rows` cells laid
    /// over `visible`, the display's visible frame, with the lines the
    /// grid overlay draws and the sweeps step along.
    ///
    /// The window keeps its size: the edge facing the arrow moves to the
    /// nearest grid line in that direction (a whole cell when already on a
    /// line, less when between two lines) and the opposite edge follows.
    /// The facing edge counts as at the display's edge when it is within
    /// `edgeTolerance` of it or past it, so a window hanging off the
    /// display is handed to the next display rather than pushed further
    /// out.
    public static func move(_ window: Rect, _ direction: Direction, columns: Int, rows: Int, in visible: Rect) -> Rect? {
        switch direction {
        case .left:
            let lines = edges(from: visible.minX, length: visible.width, count: columns)
            guard window.minX > lines[0] + edgeTolerance, let line = lineBelow(window.minX, in: lines) else { return nil }
            return Rect(x: line, y: window.y, width: window.width, height: window.height)
        case .right:
            let lines = edges(from: visible.minX, length: visible.width, count: columns)
            guard window.maxX < lines[columns] - edgeTolerance, let line = lineAbove(window.maxX, in: lines) else { return nil }
            return Rect(x: line - window.width, y: window.y, width: window.width, height: window.height)
        case .down:
            let lines = edges(from: visible.minY, length: visible.height, count: rows)
            guard window.minY > lines[0] + edgeTolerance, let line = lineBelow(window.minY, in: lines) else { return nil }
            return Rect(x: window.x, y: line, width: window.width, height: window.height)
        case .up:
            let lines = edges(from: visible.minY, length: visible.height, count: rows)
            guard window.maxY < lines[rows] - edgeTolerance, let line = lineAbove(window.maxY, in: lines) else { return nil }
            return Rect(x: window.x, y: line - window.height, width: window.width, height: window.height)
        }
    }

    /// The index in `frames` of the display beyond `source`'s edge on
    /// `direction`'s side, or nil when there is none. `source` and
    /// `frames` are display frames (`NSScreen.frame`, whole displays, not
    /// visible frames), which macOS lays out edge to edge. A display
    /// qualifies when its far edge is `source`'s near edge (within
    /// `edgeTolerance`) and its span along that edge overlaps `window`'s
    /// span by more than zero; a display that only touches at a corner
    /// does not. With several, the one overlapping `window` most wins.
    /// `source` itself is never returned.
    public static func adjacentDisplay(to source: Rect, _ direction: Direction, spanning window: Rect, among frames: [Rect]) -> Int? {
        var best: Int?
        var bestOverlap = 0.0
        for (index, frame) in frames.enumerated() where frame != source {
            let sharesEdge: Bool
            let overlap: Double
            switch direction {
            case .left:
                sharesEdge = abs(frame.maxX - source.minX) <= edgeTolerance
                overlap = min(frame.maxY, window.maxY) - max(frame.minY, window.minY)
            case .right:
                sharesEdge = abs(frame.minX - source.maxX) <= edgeTolerance
                overlap = min(frame.maxY, window.maxY) - max(frame.minY, window.minY)
            case .down:
                sharesEdge = abs(frame.maxY - source.minY) <= edgeTolerance
                overlap = min(frame.maxX, window.maxX) - max(frame.minX, window.minX)
            case .up:
                sharesEdge = abs(frame.minY - source.maxY) <= edgeTolerance
                overlap = min(frame.maxX, window.maxX) - max(frame.minX, window.minX)
            }
            if sharesEdge && overlap > bestOverlap {
                best = index
                bestOverlap = overlap
            }
        }
        return best
    }

    /// The frame a window gets when a move hotkey carries it from the
    /// display whose visible frame is `source` (grid `sourceLayout`) onto
    /// the display beyond `direction`'s edge, whose visible frame is
    /// `destination` (grid `destinationLayout`). The window lands against
    /// the destination's near edge (moving left, its right edge on the
    /// destination's right edge) and keeps its size in grid cells: its
    /// width divided by the source cell width, rounded, at least 1 and at
    /// most the destination's column count; rows likewise. Across the
    /// other axis its position is kept as a cell index: moving left or
    /// right, the row its top edge is in on the source grid is its top row
    /// on the destination, clamped so it fits; moving up or down, the
    /// column of its left edge likewise. The result comes from
    /// `gridFrame`, so a carried window sits on the destination's lines.
    public static func carry(_ window: Rect, _ direction: Direction,
                             from source: Rect, _ sourceLayout: GridLayout,
                             to destination: Rect, _ destinationLayout: GridLayout) -> Rect {
        let cols = destinationLayout.columns, rows = destinationLayout.rows
        let spanColumns = cellsSpanned(window.width, cellSize: source.width / Double(sourceLayout.columns), limit: cols)
        let spanRows = cellsSpanned(window.height, cellSize: source.height / Double(sourceLayout.rows), limit: rows)
        // The window's top-left cell on the source grid, for the index kept
        // across the other axis. Row 0 is the top row in `gridCell`. The
        // point is one `edgeTolerance` inside the corner, so a top edge
        // that reads back half a point above its grid line still counts in
        // the row below the line, where the window visibly is.
        let topLeft = gridCell(at: Point(x: window.minX + edgeTolerance, y: window.maxY - edgeTolerance),
                               columns: sourceLayout.columns, rows: sourceLayout.rows, in: source)
        let column: Int, row: Int
        switch direction {
        case .left:
            column = cols - spanColumns
            row = min(topLeft.row, rows - spanRows)
        case .right:
            column = 0
            row = min(topLeft.row, rows - spanRows)
        case .up:
            // Against the destination's bottom edge: the window's lowest
            // row is the last row, so its top row is that many rows up.
            row = rows - spanRows
            column = min(topLeft.column, cols - spanColumns)
        case .down:
            row = 0
            column = min(topLeft.column, cols - spanColumns)
        }
        return gridFrame(from: GridCell(column: column, row: row),
                         to: GridCell(column: column + spanColumns - 1, row: row + spanRows - 1),
                         columns: cols, rows: rows, in: destination)
    }

    /// How many cells of `cellSize` a length covers, rounded to the
    /// nearest whole cell, at least 1 and at most `limit`. A zero or
    /// negative cell size (a degenerate display) counts as one cell.
    private static func cellsSpanned(_ length: Double, cellSize: Double, limit: Int) -> Int {
        guard cellSize > 0 else { return 1 }
        return min(limit, max(1, Int((length / cellSize).rounded())))
    }
}
