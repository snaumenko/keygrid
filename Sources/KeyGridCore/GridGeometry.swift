/// One cell of the grid overlay, named by its column and row.
///
/// Column 0 is the leftmost column and row 0 is the *top* row, the way a
/// person reads a grid and the way the overlay draws it. AppKit's y axis
/// grows upward, so a cell's row is not its position in AppKit
/// coordinates; `Geometry.gridFrame(from:to:columns:rows:in:)` does that
/// conversion. A `GridCell` knows nothing about the grid's size or the
/// frame it lies in: it is two indexes, valid only for the grid they were
/// computed for.
public struct GridCell: Equatable, Hashable, Sendable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// The grid overlay's arithmetic: which cell a point falls in, and the
/// frame a drag between two cells selects. Pure functions over `Rect`,
/// `Point`, and the grid size; nothing here draws, reads the mouse, or
/// moves a window. `GridView` in `Sources/KeyGrid/GridOverlay.swift` calls
/// these with the display's visible frame and the mouse position, both
/// shifted so the display's bottom-left corner is (0, 0).
///
/// Cell edges are rounded to whole points by the rule
/// `Geometry.frame(for:in:)` uses for the edges of a half: edge `i` of
/// `columns` is the absolute coordinate `(minX + width * i / columns)`
/// rounded with `Double.rounded()`, which sends a half away from zero
/// (2720.5 becomes 2721). Rounding the absolute coordinate, not the
/// offset from the frame's edge, is what makes a 2×2 grid's cells equal
/// the four quarter placements to the point, ties included. Edge 0
/// is pinned to `minX` and edge `columns` to `maxX`, so the cells tile
/// the frame exactly even when the frame itself has fractional edges, and
/// the odd points of a width that does not divide evenly are spread
/// across the grid rather than all given to the last column. The same
/// edges decide which cell a point is in, so a point and the cell drawn
/// around it always agree.
extension Geometry {
    /// The cell under `point` in a `columns` × `rows` grid laid over
    /// `frame`. A point outside the frame is clamped to the nearest edge
    /// cell, so a drag that leaves the display keeps selecting the border
    /// cells. A point exactly on a shared edge belongs to the cell to its
    /// right or below it, so every point belongs to exactly one cell and
    /// the frame of a cell contains its own left and top edges.
    public static func gridCell(at point: Point, columns: Int, rows: Int, in frame: Rect) -> GridCell {
        let xEdges = edges(from: frame.minX, length: frame.width, count: columns)
        // y edges run from the top down so that index 0 is row 0, the top row.
        let yEdges = edges(from: frame.maxY, length: -frame.height, count: rows)
        return GridCell(column: index(of: point.x, in: xEdges, ascending: true),
                        row: index(of: point.y, in: yEdges, ascending: false))
    }

    /// The frame spanned by the cells from `a` to `b`, inclusive, in a
    /// `columns` × `rows` grid laid over `frame`. The order of `a` and `b`
    /// does not matter: a drag up and left selects the same rectangle as
    /// the same drag down and right. `a == b` gives one cell's frame, which
    /// is what the overlay draws for each cell and for a plain click. Both
    /// cells must lie in the grid; a cell computed for a grid of another
    /// size is a programming error and stops the program with a message,
    /// rather than silently selecting a different rectangle.
    public static func gridFrame(from a: GridCell, to b: GridCell, columns: Int, rows: Int, in frame: Rect) -> Rect {
        for cell in [a, b] {
            precondition((0..<columns).contains(cell.column) && (0..<rows).contains(cell.row),
                         "cell (\(cell.column), \(cell.row)) lies outside a \(columns)×\(rows) grid")
        }
        let xEdges = edges(from: frame.minX, length: frame.width, count: columns)
        let yEdges = edges(from: frame.maxY, length: -frame.height, count: rows)
        let left = xEdges[min(a.column, b.column)]
        let right = xEdges[max(a.column, b.column) + 1]
        // Row 0 is the top, so the smaller row index is the higher edge.
        let top = yEdges[min(a.row, b.row)]
        let bottom = yEdges[max(a.row, b.row) + 1]
        return Rect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// The `count + 1` edge positions of `count` cells laid along one axis,
    /// starting at `start` and covering `length`. A negative `length` lays
    /// the cells in the other direction, which is how rows are counted from
    /// the top in AppKit coordinates. Internal rather than private because
    /// `Geometry.sweep` and `Geometry.move` in `EdgeGeometry.swift` walk
    /// the same edges, so a sweep or a move lands on the lines the overlay
    /// draws. The first edge is exactly `start` and
    /// the last exactly `start + length`, unrounded, so the cells end where
    /// the frame ends even if the frame has a fractional edge; every edge
    /// between them is the absolute coordinate rounded to a whole point.
    static func edges(from start: Double, length: Double, count: Int) -> [Double] {
        precondition(count >= 1, "a grid needs at least one cell along each axis; Geometry.gridLayout(for:size:) never produces fewer")
        var result = (0...count).map { (start + length * Double($0) / Double(count)).rounded() }
        result[0] = start
        result[count] = start + length
        return result
    }

    /// The index of the cell that contains `value` along one axis, given
    /// that axis's edges. When the edges ascend (x), it is the index of the
    /// largest edge at or below `value`; when they descend (y counted from
    /// the top), of the smallest edge at or above `value`. Clamped: a value
    /// before the first edge gives 0 and one at or beyond the last edge
    /// gives the last cell.
    private static func index(of value: Double, in edges: [Double], ascending: Bool) -> Int {
        // Interior edges only: cell 0 is the answer when no interior edge is
        // at or before `value`, and the last edge closes the last cell rather
        // than opening a new one. A grid of one cell has no interior edge
        // and the loop is empty.
        var cell = 0
        for i in 1..<(edges.count - 1) where ascending ? edges[i] <= value : edges[i] >= value {
            cell = i
        }
        return cell
    }
}

/// How many cells the grid overlay has across and down one display: the
/// result of `Geometry.gridLayout(for:size:)`. Two counts and nothing
/// else; it does not know which display it was computed for.
public struct GridLayout: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

extension Geometry {
    /// The grid layout for a display whose visible frame is `frame`, from
    /// the one number the config holds, `grid.size`: the cell count along
    /// the display's shorter edge. The count along the longer edge is
    /// `size` scaled by the display's shape (longer edge ÷ shorter edge),
    /// rounded to the nearest multiple of 6 so halves and thirds still fall
    /// on cell edges, and never below 6. A landscape or square display puts
    /// `size` on the rows; a portrait display puts it on the columns, so
    /// the same display turned on its side gets the same grid turned on
    /// its side, and cells stay roughly square either way.
    ///
    /// With `size` 6: a 16:9 display gets 12×6 (6 × 1.78 = 10.7, and the
    /// nearest multiple of 6 is 12), 4:3 gets 6×6 (8 is nearer 6 than
    /// 12), 21:9 gets 12×6, and
    /// 32:9 gets 24×6. `size` must be at least 1; `Config` only allows
    /// multiples of 6 from 6 to 36, which is where the halves-and-thirds
    /// property of the short edge comes from.
    public static func gridLayout(for frame: Rect, size: Int) -> GridLayout {
        precondition(size >= 1, "a grid needs at least one cell along each axis; the config limits sizes to 6…36")
        let landscape = frame.width >= frame.height
        let short = landscape ? frame.height : frame.width
        let long = landscape ? frame.width : frame.height
        // A display with a zero or negative edge would divide by zero; no
        // real display has one, so treat it as square rather than crash.
        let ratio = short > 0 ? long / short : 1
        // Nearest multiple of 6, a tie going up: on a 3:2 display with size
        // 6, 6 × 1.5 = 9, 9 / 6 = 1.5, and `rounded()` sends a half away
        // from zero, so 2 → 12.
        let longCount = max(6, Int((Double(size) * ratio / 6).rounded()) * 6)
        return landscape
            ? GridLayout(columns: longCount, rows: size)
            : GridLayout(columns: size, rows: longCount)
    }
}
