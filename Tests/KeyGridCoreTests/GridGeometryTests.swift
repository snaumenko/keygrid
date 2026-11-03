import Testing
@testable import KeyGridCore

// A display to the right of and above the primary, menu bar and Dock taken
// off: a non-zero origin and odd sizes, so cell edges need rounding.
private let visible = Rect(x: 1920, y: 300, width: 1601, height: 905)
private let columns = 16, rows = 12

private func cell(_ column: Int, _ row: Int) -> GridCell { GridCell(column: column, row: row) }
private func frame(_ a: GridCell, _ b: GridCell, in rect: Rect = visible, columns: Int = columns, rows: Int = rows) -> Rect {
    Geometry.gridFrame(from: a, to: b, columns: columns, rows: rows, in: rect)
}

@Suite struct GridSelection {
    // A drag from one corner cell to another selects the same rectangle
    // whichever corner the drag starts from.
    @Test func reverseDragEqualsForwardDrag() {
        #expect(frame(cell(2, 3), cell(9, 7)) == frame(cell(9, 7), cell(2, 3)))
        // Across one axis only, each way.
        #expect(frame(cell(2, 7), cell(9, 3)) == frame(cell(9, 3), cell(2, 7)))
        #expect(frame(cell(2, 7), cell(9, 3)) == frame(cell(2, 3), cell(9, 7)))
    }

    @Test func fullDragIsTheFrame() {
        #expect(frame(cell(0, 0), cell(columns - 1, rows - 1)) == visible)
    }

    @Test func rowZeroIsTheTop() {
        let topLeft = frame(cell(0, 0), cell(0, 0))
        #expect(topLeft.minX == visible.minX)
        #expect(topLeft.maxY == visible.maxY)
        let bottomRight = frame(cell(columns - 1, rows - 1), cell(columns - 1, rows - 1))
        #expect(bottomRight.maxX == visible.maxX)
        #expect(bottomRight.minY == visible.minY)
    }

    // The 7×5 frame is smaller than the grid: most cells collapse to zero
    // width or height and must still tile without going negative.
    @Test(arguments: [visible, Rect(x: -1601, y: -200, width: 1601, height: 905), Rect(x: 0, y: 0, width: 7, height: 5)])
    func cellsTileTheFrameExactly(_ rect: Rect) {
        var widths = 0.0
        for c in 0..<columns {
            let here = frame(cell(c, 0), cell(c, 0), in: rect)
            widths += here.width
            #expect(here.width >= 0)
            if c > 0 {
                let previous = frame(cell(c - 1, 0), cell(c - 1, 0), in: rect)
                #expect(previous.maxX == here.minX)
            }
        }
        #expect(widths == rect.width)

        var heights = 0.0
        for r in 0..<rows {
            let here = frame(cell(0, r), cell(0, r), in: rect)
            heights += here.height
            if r > 0 {
                let above = frame(cell(0, r - 1), cell(0, r - 1), in: rect)
                #expect(above.minY == here.maxY)
            }
        }
        #expect(heights == rect.height)
    }

    @Test func oddPointsAreSpreadNotPiledOnTheLastCell() {
        // 1601 / 16 = 100.0625: fifteen cells of 100 and one of 101 either
        // way, but rounded edges put the 101 in column 7 (edge 8 is
        // 1920 + 800.5, rounded away from zero to 2721), not in the last
        // column. A width of 1607 has seven extra points, and they land in
        // seven different columns.
        let widths = (0..<columns).map { frame(cell($0, 0), cell($0, 0)).width }
        #expect(widths.filter { $0 == 101 }.count == 1)
        #expect(widths[7] == 101)
        #expect(widths[columns - 1] == 100)
        let wide = Rect(x: 0, y: 0, width: 1607, height: 905)
        let wideWidths = (0..<columns).map { frame(cell($0, 0), cell($0, 0), in: wide).width }
        #expect(wideWidths.filter { $0 == 101 }.count == 7)
    }

    // Holds because `visible` has whole-point edges, as AppKit frames do.
    @Test func edgesAreWholePoints() {
        let r = frame(cell(3, 4), cell(5, 9))
        #expect(r.minX == r.minX.rounded() && r.maxX == r.maxX.rounded())
        #expect(r.minY == r.minY.rounded() && r.maxY == r.maxY.rounded())
    }

    @Test func oneByOneGridIsTheFrame() {
        #expect(frame(cell(0, 0), cell(0, 0), columns: 1, rows: 1) == visible)
    }

    // The grid and the half placements must agree to the point, or a window
    // placed with the overlay sits one point off one placed with a hotkey.
    // Ties (odd widths) are where an offset-based rounding would differ.
    @Test(arguments: [visible, Rect(x: -1601, y: -200, width: 1601, height: 905)])
    func twoByOneGridEqualsTheHalfPlacements(_ rect: Rect) {
        #expect(frame(cell(0, 0), cell(0, 0), in: rect, columns: 2, rows: 1) == Geometry.frame(for: .leftHalf, in: rect))
        #expect(frame(cell(1, 0), cell(1, 0), in: rect, columns: 2, rows: 1) == Geometry.frame(for: .rightHalf, in: rect))
        // On the 12×6 grid a display actually gets, the halves are six columns.
        #expect(frame(cell(0, 0), cell(5, 5), in: rect, columns: 12, rows: 6) == Geometry.frame(for: .leftHalf, in: rect))
        #expect(frame(cell(6, 0), cell(11, 5), in: rect, columns: 12, rows: 6) == Geometry.frame(for: .rightHalf, in: rect))
    }

    @Test func singleRowAndSingleColumnGrids() {
        let row = (0..<5).map { frame(cell($0, 0), cell($0, 0), columns: 5, rows: 1) }
        #expect(row.map(\.height) == Array(repeating: visible.height, count: 5))
        #expect(row.map(\.width).reduce(0, +) == visible.width)
        let column = (0..<5).map { frame(cell(0, $0), cell(0, $0), columns: 1, rows: 5) }
        #expect(column.map(\.width) == Array(repeating: visible.width, count: 5))
        #expect(column.map(\.height).reduce(0, +) == visible.height)
    }

    @Test func fractionalFrameStillEndsAtItsOwnEdges() {
        let rect = Rect(x: 0.5, y: 0.25, width: 1601.5, height: 905.5)
        #expect(frame(cell(0, 0), cell(columns - 1, rows - 1), in: rect) == rect)
    }
}

@Suite struct GridHitTesting {
    private func cellAt(_ x: Double, _ y: Double, in rect: Rect = visible) -> GridCell {
        Geometry.gridCell(at: Point(x: x, y: y), columns: columns, rows: rows, in: rect)
    }

    @Test func centreOfEveryCellMapsBackToIt() {
        for c in 0..<columns {
            for r in 0..<rows {
                let here = frame(cell(c, r), cell(c, r))
                let centre = Point(x: here.minX + here.width / 2, y: here.minY + here.height / 2)
                #expect(Geometry.gridCell(at: centre, columns: columns, rows: rows, in: visible) == cell(c, r))
            }
        }
    }

    @Test func cornersOfTheFrame() {
        #expect(cellAt(visible.minX, visible.maxY) == cell(0, 0))
        #expect(cellAt(visible.maxX, visible.minY) == cell(columns - 1, rows - 1))
        #expect(cellAt(visible.minX, visible.minY) == cell(0, rows - 1))
        #expect(cellAt(visible.maxX, visible.maxY) == cell(columns - 1, 0))
    }

    @Test func pointsOutsideClampToTheBorderCells() {
        #expect(cellAt(visible.minX - 500, visible.minY + 10) == cell(0, rows - 1))
        #expect(cellAt(visible.maxX + 500, visible.maxY - 10) == cell(columns - 1, 0))
        #expect(cellAt(visible.minX + 10, visible.maxY + 500) == cell(0, 0))
        #expect(cellAt(visible.minX + 10, visible.minY - 500) == cell(0, rows - 1))
    }

    @Test func sharedEdgeBelongsToTheCellRightOrBelow() {
        let second = frame(cell(1, 1), cell(1, 1))
        // Its left edge is shared with column 0; its top edge with row 0.
        #expect(cellAt(second.minX, second.maxY) == cell(1, 1))
        // One point inside the previous cell on each axis.
        #expect(cellAt(second.minX - 1, second.maxY + 1) == cell(0, 0))
    }

    @Test func oneByOneGridHasOneCell() {
        let far = Point(x: -9999, y: 9999)
        #expect(Geometry.gridCell(at: far, columns: 1, rows: 1, in: visible) == cell(0, 0))
    }

    @Test(arguments: [visible, Rect(x: -1601, y: -200, width: 1601, height: 905)])
    func topLeftCornerOfEveryCellMapsBackToIt(_ rect: Rect) {
        // The top-left corner lies on the cell's own left and top edges, both
        // shared with its neighbours, so the right/below rule is tested at
        // every interior edge of the grid, not just one.
        for c in 0..<columns {
            for r in 0..<rows {
                let here = frame(cell(c, r), cell(c, r), in: rect)
                #expect(cellAt(here.minX, here.maxY, in: rect) == cell(c, r))
                // Just inside the opposite corner is still the same cell.
                #expect(cellAt(here.maxX - 0.5, here.minY + 0.5, in: rect) == cell(c, r))
            }
        }
    }
}

@Suite struct GridLayoutFromSize {
    private func layout(_ width: Double, _ height: Double, size: Int = 6) -> GridLayout {
        Geometry.gridLayout(for: Rect(x: 0, y: 0, width: width, height: height), size: size)
    }

    @Test func sixteenByNineGetsTwelveBySix() {
        // 6 × 16/9 = 10.67 → 12.
        #expect(layout(1920, 1080) == GridLayout(columns: 12, rows: 6))
        // A visible frame, menu bar and Dock taken off, is not exactly 16:9
        // but lands on the same count.
        #expect(layout(3761, 2129) == GridLayout(columns: 12, rows: 6))
    }

    @Test func portraitIsTheSameGridTurned() {
        #expect(layout(1080, 1920) == GridLayout(columns: 6, rows: 12))
        #expect(layout(1080, 1920, size: 12) == GridLayout(columns: 12, rows: 24))
    }

    @Test func squareCountsAsLandscape() {
        #expect(layout(1000, 1000) == GridLayout(columns: 6, rows: 6))
        #expect(layout(1000, 1000, size: 18) == GridLayout(columns: 18, rows: 18))
    }

    @Test func nearlySquareDisplaysRoundDownToSix() {
        // 4:3 → 8 → 6. 5:4 → 7.5 → 6.
        #expect(layout(1600, 1200) == GridLayout(columns: 6, rows: 6))
        #expect(layout(1280, 1024) == GridLayout(columns: 6, rows: 6))
    }

    @Test func longEdgeIsNeverBelowSix() {
        // Every size Config allows is 6 or more, so for real inputs the long
        // count is at least 6 by arithmetic. The floor only acts for sizes
        // below 6, which the function accepts: 1 × 1 / 6 rounds to 0 → 6.
        #expect(layout(1000, 1000, size: 1) == GridLayout(columns: 6, rows: 1))
        #expect(layout(1000, 1920, size: 2) == GridLayout(columns: 2, rows: 6))
    }

    @Test func aDegenerateFrameIsTreatedAsSquare() {
        // No real display has a zero edge; the function must not divide by
        // zero if handed one.
        #expect(layout(1000, 0) == GridLayout(columns: 6, rows: 6))
        #expect(layout(0, 0) == GridLayout(columns: 6, rows: 6))
    }

    @Test func roundsToTheNearestMultipleOfSix() {
        // 16:10 → 9.6 → 12. 21:9 → 14 → 12. 32:9 → 21.3 → 24.
        #expect(layout(1920, 1200) == GridLayout(columns: 12, rows: 6))
        #expect(layout(2560, 1080) == GridLayout(columns: 12, rows: 6))
        #expect(layout(5120, 1440) == GridLayout(columns: 24, rows: 6))
        // A tie goes up: 3:2 → 9, halfway between 6 and 12 → 12. 9 / 6 = 1.5
        // is exact in Double, so this is a true tie for `rounded()`.
        #expect(layout(1500, 1000) == GridLayout(columns: 12, rows: 6))
    }

    @Test func sizeScalesTheLongEdge() {
        // 12 × 16/9 = 21.3 → 24; 36 × 16/9 = 64 → 66.
        #expect(layout(1920, 1080, size: 12) == GridLayout(columns: 24, rows: 12))
        #expect(layout(1920, 1080, size: 36) == GridLayout(columns: 66, rows: 36))
    }

    @Test func aSizeThatIsNotAMultipleOfSixStillLaysOut() {
        // The function only needs size ≥ 1; Config rejects 7 before it gets here.
        #expect(layout(1920, 1080, size: 7) == GridLayout(columns: 12, rows: 7))
    }
}
