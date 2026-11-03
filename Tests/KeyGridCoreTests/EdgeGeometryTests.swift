import Testing
@testable import KeyGridCore

// A 1200×600 visible frame with a non-zero origin and a 12×6 grid: every
// cell is exactly 100×100 points, so expected frames can be written down.
private let visible = Rect(x: 100, y: 50, width: 1200, height: 600)

private func sweep(_ window: Rect, _ direction: Direction, columns: Int = 12, rows: Int = 6, in frame: Rect = visible) -> Rect {
    Geometry.sweep(window, direction, columns: columns, rows: rows, in: frame)
}

@Suite struct SweepGrow {
    @Test func leftMovesTheLeftEdgeOneColumn() {
        // Right half: x 700…1300.
        let rightHalf = Rect(x: 700, y: 50, width: 600, height: 600)
        #expect(sweep(rightHalf, .left) == Rect(x: 600, y: 50, width: 700, height: 600))
    }

    @Test func sixPressesFromTheRightHalfFillTheWidth() {
        var frame = Rect(x: 700, y: 50, width: 600, height: 600)
        for _ in 0..<6 { frame = sweep(frame, .left) }
        #expect(frame == visible)
    }

    @Test func rightMirrorsLeft() {
        let leftHalf = Rect(x: 100, y: 50, width: 600, height: 600)
        #expect(sweep(leftHalf, .right) == Rect(x: 100, y: 50, width: 700, height: 600))
    }

    @Test func upAndDownWorkOnRows() {
        // Bottom half: y 50…350.
        let bottomHalf = Rect(x: 100, y: 50, width: 1200, height: 300)
        #expect(sweep(bottomHalf, .up) == Rect(x: 100, y: 50, width: 1200, height: 400))
        let topHalf = Rect(x: 100, y: 350, width: 1200, height: 300)
        #expect(sweep(topHalf, .down) == Rect(x: 100, y: 250, width: 1200, height: 400))
    }

    @Test func anEdgeBetweenLinesSnapsToTheLine() {
        // Left edge at 650, between the lines at 600 and 700: one press
        // moves it 50 points, onto 600, not a full column to 550.
        let window = Rect(x: 650, y: 50, width: 650, height: 600)
        #expect(sweep(window, .left) == Rect(x: 600, y: 50, width: 700, height: 600))
    }

    @Test func theOtherAxisIsUntouched() {
        let window = Rect(x: 700, y: 123.5, width: 300, height: 77.25)
        let after = sweep(window, .left)
        #expect(after.y == 123.5)
        #expect(after.height == 77.25)
        #expect(after.maxX == 1000)
    }

    @Test func aFractionalEdgeWithinTheToleranceCountsAsOnTheLine() {
        // 700.5 is on the line at 700 for sweeping purposes, so the press
        // moves a whole column to 600, not half a point to 700.
        let window = Rect(x: 700.5, y: 50, width: 599.5, height: 600)
        #expect(sweep(window, .left).minX == 600)
    }
}

@Suite struct SweepShrink {
    @Test func atTheEdgeTheOppositeEdgeMovesInstead() {
        #expect(sweep(visible, .left) == Rect(x: 100, y: 50, width: 1100, height: 600))
        #expect(sweep(visible, .right) == Rect(x: 200, y: 50, width: 1100, height: 600))
        #expect(sweep(visible, .up) == Rect(x: 100, y: 150, width: 1200, height: 500))
        #expect(sweep(visible, .down) == Rect(x: 100, y: 50, width: 1200, height: 500))
    }

    @Test func elevenPressesFromFullWidthLeaveOneColumn() {
        var frame = visible
        for _ in 0..<11 { frame = sweep(frame, .left) }
        #expect(frame == Rect(x: 100, y: 50, width: 100, height: 600))
        // The twelfth press, and every press after it, changes nothing.
        #expect(sweep(frame, .left) == frame)
    }

    @Test func aWindowHangingOffTheDisplayShrinksFirst() {
        // Left edge 50 points past the display's left edge at 100.
        let hanging = Rect(x: 50, y: 50, width: 650, height: 600)
        #expect(sweep(hanging, .left) == Rect(x: 50, y: 50, width: 550, height: 600))
    }

    @Test func rightAndUpShrinkToOneCellToo() {
        // The mirror of the left walk: eleven presses from full width leave
        // the rightmost column, and the twelfth does nothing.
        var frame = visible
        for _ in 0..<11 { frame = sweep(frame, .right) }
        #expect(frame == Rect(x: 1200, y: 50, width: 100, height: 600))
        #expect(sweep(frame, .right) == frame)
        // Between lines: left edge 1150 → 1200, the last line in from the right.
        #expect(sweep(Rect(x: 1150, y: 50, width: 150, height: 600), .right) == frame)
        // Up on rows: the top row stays, from on a line and from between lines.
        let topRow = Rect(x: 100, y: 550, width: 1200, height: 100)
        #expect(sweep(topRow, .up) == topRow)
        #expect(sweep(Rect(x: 100, y: 525, width: 1200, height: 125), .up) == topRow)
    }

    @Test func aWindowWiderThanTheDisplayShrinksOntoTheFarEdgeFirst() {
        // Hanging off both sides (0…1500 over 100…1300): the facing edge
        // counts as at the display edge, so the far edge snaps onto the
        // display's far edge; the hanging near edge is left where it is.
        let wide = Rect(x: 0, y: 50, width: 1500, height: 600)
        #expect(sweep(wide, .left) == Rect(x: 0, y: 50, width: 1300, height: 600))
        #expect(sweep(wide, .right) == Rect(x: 100, y: 50, width: 1400, height: 600))
    }

    @Test func exactlyOnePointOffCountsAsOnTheLine() {
        // 101 is within the one-point tolerance of the display edge at 100,
        // so the press shrinks; 101.5 is not, so it grows onto 100.
        #expect(sweep(Rect(x: 101, y: 50, width: 599, height: 600), .left) == Rect(x: 101, y: 50, width: 499, height: 600))
        #expect(sweep(Rect(x: 101.5, y: 50, width: 598.5, height: 600), .left).minX == 100)
        // The same boundary against an interior line at 700.
        #expect(sweep(Rect(x: 701, y: 50, width: 599, height: 600), .left).minX == 600)
        #expect(sweep(Rect(x: 701.5, y: 50, width: 598.5, height: 600), .left).minX == 700)
    }

    @Test func shrinkStopsAtOneColumnEvenFromBetweenLines() {
        // Right edge at 250, between 200 and 300; the nearest line below is
        // 200, which is the first line in from the edge, so it is allowed.
        let window = Rect(x: 100, y: 50, width: 150, height: 600)
        #expect(sweep(window, .left) == Rect(x: 100, y: 50, width: 100, height: 600))
        // Right edge at 150: the only line below is the display edge
        // itself, which would leave no column, so nothing moves.
        let thin = Rect(x: 100, y: 50, width: 50, height: 600)
        #expect(sweep(thin, .left) == thin)
    }
}

@Suite struct SweepOnOtherGrids {
    @Test func aOneColumnGridGrowsToFullAndNeverShrinks() {
        // Config never produces one column (sizes start at 6), but the
        // function accepts it: the only lines are the display's edges.
        let window = Rect(x: 400, y: 50, width: 300, height: 600)
        let grown = sweep(window, .left, columns: 1, rows: 1)
        #expect(grown == Rect(x: 100, y: 50, width: 600, height: 600))
        #expect(sweep(visible, .left, columns: 1, rows: 1) == visible)
    }

    @Test func portraitGridUsesItsOwnCounts() {
        // 600×1200 visible frame, 6 columns × 12 rows, 100-point cells.
        let portrait = Rect(x: 0, y: 0, width: 600, height: 1200)
        let bottom = Rect(x: 0, y: 0, width: 600, height: 600)
        #expect(sweep(bottom, .up, columns: 6, rows: 12, in: portrait) == Rect(x: 0, y: 0, width: 600, height: 700))
    }

    @Test func linesMatchTheGridOverlay() {
        // The lines a sweep lands on are the overlay's cell edges, rounded
        // the same way, even on a width that does not divide evenly.
        let odd = Rect(x: 1920, y: 300, width: 1601, height: 905)
        let cell = Geometry.gridFrame(from: GridCell(column: 5, row: 0), to: GridCell(column: 11, row: 5), columns: 12, rows: 6, in: odd)
        let grown = sweep(cell, .left, columns: 12, rows: 6, in: odd)
        let expected = Geometry.gridFrame(from: GridCell(column: 4, row: 0), to: GridCell(column: 11, row: 5), columns: 12, rows: 6, in: odd)
        #expect(grown == expected)
    }
}

// Two displays side by side: `left` ends where `visible` (x 100…1300)
// begins. Their display frames, for adjacency, are the same rectangles
// here; a real display's visible frame is smaller than its frame.
private let leftDisplay = Rect(x: -1100, y: 50, width: 1200, height: 600)

private func move(_ window: Rect, _ direction: Direction, columns: Int = 12, rows: Int = 6, in frame: Rect = visible) -> Rect? {
    Geometry.move(window, direction, columns: columns, rows: rows, in: frame)
}

@Suite struct MoveStep {
    @Test func movesOneCellKeepingTheSize() {
        let window = Rect(x: 700, y: 250, width: 300, height: 200)
        #expect(move(window, .left) == Rect(x: 600, y: 250, width: 300, height: 200))
        #expect(move(window, .right) == Rect(x: 800, y: 250, width: 300, height: 200))
        #expect(move(window, .up) == Rect(x: 700, y: 350, width: 300, height: 200))
        #expect(move(window, .down) == Rect(x: 700, y: 150, width: 300, height: 200))
    }

    @Test func anEdgeBetweenLinesSnapsFirst() {
        // Left edge 650 → 600; right edge 950 → 1000 (window 650…950).
        let window = Rect(x: 650, y: 50, width: 300, height: 600)
        #expect(move(window, .left) == Rect(x: 600, y: 50, width: 300, height: 600))
        #expect(move(window, .right) == Rect(x: 700, y: 50, width: 300, height: 600))
    }

    @Test func atTheEdgeReturnsNil() {
        let leftColumn = Rect(x: 100, y: 50, width: 100, height: 600)
        #expect(move(leftColumn, .left) == nil)
        #expect(move(Rect(x: 1200, y: 50, width: 100, height: 600), .right) == nil)
        #expect(move(Rect(x: 100, y: 550, width: 1200, height: 100), .up) == nil)
        #expect(move(Rect(x: 100, y: 50, width: 1200, height: 100), .down) == nil)
        // Within the tolerance, and hanging past the edge, count the same.
        #expect(move(Rect(x: 100.5, y: 50, width: 100, height: 600), .left) == nil)
        #expect(move(Rect(x: 20, y: 50, width: 100, height: 600), .left) == nil)
        #expect(move(Rect(x: 1199.5, y: 50, width: 100, height: 600), .right) == nil)
        #expect(move(Rect(x: 1250, y: 50, width: 100, height: 600), .right) == nil)
        #expect(move(Rect(x: 100, y: 549.5, width: 1200, height: 100), .up) == nil)
        #expect(move(Rect(x: 100, y: 20, width: 1200, height: 100), .down) == nil)
    }

    @Test func theOtherAxisIsUntouched() {
        let window = Rect(x: 700, y: 123.5, width: 300, height: 77.25)
        #expect(move(window, .left) == Rect(x: 600, y: 123.5, width: 300, height: 77.25))
    }
}

@Suite struct AdjacentDisplays {
    let frames = [visible, leftDisplay]

    @Test func findsTheDisplayBeyondTheEdge() {
        let window = Rect(x: 100, y: 200, width: 300, height: 200)
        #expect(Geometry.adjacentDisplay(to: visible, .left, spanning: window, among: frames) == 1)
        #expect(Geometry.adjacentDisplay(to: leftDisplay, .right, spanning: window, among: frames) == 0)
        #expect(Geometry.adjacentDisplay(to: visible, .right, spanning: window, among: frames) == nil)
        #expect(Geometry.adjacentDisplay(to: visible, .up, spanning: window, among: frames) == nil)
    }

    @Test func aDisplayTouchingOnlyAtACornerDoesNotCount() {
        // Above and to the left of `visible`: shares the left edge's line
        // but none of the window's vertical span.
        let corner = Rect(x: -1100, y: 650, width: 1200, height: 600)
        let window = Rect(x: 100, y: 50, width: 300, height: 600)
        #expect(Geometry.adjacentDisplay(to: visible, .left, spanning: window, among: [visible, corner]) == nil)
        // A display sharing the edge but beside the window's span (window
        // at the bottom, display covering only the top) does not count either.
        let high = Rect(x: -1100, y: 400, width: 1200, height: 600)
        let low = Rect(x: 100, y: 50, width: 300, height: 200)
        #expect(Geometry.adjacentDisplay(to: visible, .left, spanning: low, among: [visible, high]) == nil)
    }

    @Test func theDisplayOverlappingTheWindowMostWins() {
        // Two displays stacked on the left: the lower covers y 50…350, the
        // upper y 350…650. A window spanning y 200…600 overlaps the upper
        // by 250 and the lower by 150.
        let lower = Rect(x: -1100, y: 50, width: 1200, height: 300)
        let upper = Rect(x: -1100, y: 350, width: 1200, height: 300)
        let window = Rect(x: 100, y: 200, width: 300, height: 400)
        #expect(Geometry.adjacentDisplay(to: visible, .left, spanning: window, among: [visible, lower, upper]) == 2)
    }

    @Test func verticalNeighboursUseTheHorizontalSpan() {
        let above = Rect(x: 100, y: 650, width: 1200, height: 600)
        let window = Rect(x: 400, y: 450, width: 300, height: 200)
        #expect(Geometry.adjacentDisplay(to: visible, .up, spanning: window, among: [visible, above]) == 1)
        #expect(Geometry.adjacentDisplay(to: above, .down, spanning: window, among: [visible, above]) == 0)
    }
}

@Suite struct CarryAcrossDisplays {
    let landscape = GridLayout(columns: 12, rows: 6)
    // A portrait display to the left: 600 wide, 1200 tall, 6×12 cells of 100.
    let portrait = Rect(x: -500, y: -250, width: 600, height: 1200)
    let portraitLayout = GridLayout(columns: 6, rows: 12)

    @Test func landsAgainstTheNearEdgeKeepingItsSizeInCells() {
        // Three columns by two rows, top row 1, on the right display.
        let window = Rect(x: 100, y: 350, width: 300, height: 200)
        let carried = Geometry.carry(window, .left, from: visible, landscape, to: leftDisplay, landscape)
        #expect(carried == Rect(x: -200, y: 350, width: 300, height: 200))
        // Back the other way: against the left edge of `visible`.
        let back = Geometry.carry(carried, .right, from: leftDisplay, landscape, to: visible, landscape)
        #expect(back == window)
    }

    @Test func sizeInCellsIsRoundedAndClamped() {
        // 140 wide is 1.4 cells → 1; 160 is 1.6 → 2.
        let narrow = Rect(x: 100, y: 50, width: 140, height: 600)
        #expect(Geometry.carry(narrow, .left, from: visible, landscape, to: leftDisplay, landscape).width == 100)
        let wider = Rect(x: 100, y: 50, width: 160, height: 600)
        #expect(Geometry.carry(wider, .left, from: visible, landscape, to: leftDisplay, landscape).width == 200)
        // Twelve columns wide onto a six-column display: clamped to six.
        let full = Geometry.carry(visible, .left, from: visible, landscape, to: portrait, portraitLayout)
        #expect(full.width == 600 && full.minX == -500)
    }

    @Test func theRowIndexIsKeptAndClamped() {
        // Top row 1 (y 450…550) on the 6-row grid stays row 1 on the
        // 12-row portrait grid, whose rows of 100 run down from 950: row 1
        // is y 750…850, higher on the display than it was on the source.
        let window = Rect(x: 100, y: 450, width: 300, height: 100)
        let carried = Geometry.carry(window, .left, from: visible, landscape, to: portrait, portraitLayout)
        #expect(carried == Rect(x: -200, y: 750, width: 300, height: 100))
        // A bottom-row window carried onto a grid with fewer rows is clamped
        // to the last row: row 5 of 6 onto a 6-row grid stays 5; onto a
        // 3-row grid it becomes 2.
        let bottom = Rect(x: 100, y: 50, width: 300, height: 100)
        #expect(Geometry.carry(bottom, .left, from: visible, landscape, to: leftDisplay, landscape) == Rect(x: -200, y: 50, width: 300, height: 100))
        let three = GridLayout(columns: 12, rows: 3)
        let clamped = Geometry.carry(bottom, .left, from: visible, landscape, to: leftDisplay, three)
        #expect(clamped.minY == 50 && clamped.height == 200)
        // A top edge reading back half a point above its line (450.5 for
        // the line at 450) still counts as row 2, not row 1.
        let shifted = Rect(x: 100, y: 350.5, width: 300, height: 100)
        #expect(Geometry.carry(shifted, .left, from: visible, landscape, to: leftDisplay, landscape).maxY == 450)
    }

    @Test func theColumnIndexIsKeptAndClampedGoingUpOrDown() {
        // Columns 9…11 of 12 carried up onto a 6-column portrait display
        // above: the column clamps to 6 - 3 = 3, the window lands against
        // the destination's bottom edge.
        let above = Rect(x: 100, y: 650, width: 600, height: 1200)
        let window = Rect(x: 1000, y: 450, width: 300, height: 200)
        let up = Geometry.carry(window, .up, from: visible, landscape, to: above, portraitLayout)
        #expect(up == Rect(x: 400, y: 650, width: 300, height: 200))
    }

    @Test func rowsAreClampedAndTinyWindowsGetOneCell() {
        // Six rows tall onto a 3-row destination: full height, not past it.
        let tall = Rect(x: 100, y: 50, width: 300, height: 600)
        let three = GridLayout(columns: 12, rows: 3)
        #expect(Geometry.carry(tall, .left, from: visible, landscape, to: leftDisplay, three).height == 600)
        // 40×40 points is 0.4 cells each way: one cell, never zero.
        let tiny = Rect(x: 100, y: 50, width: 40, height: 40)
        #expect(Geometry.carry(tiny, .left, from: visible, landscape, to: leftDisplay, landscape) == Rect(x: 0, y: 50, width: 100, height: 100))
        // Exactly one and a half cells rounds up to two.
        let half = Rect(x: 100, y: 50, width: 150, height: 600)
        #expect(Geometry.carry(half, .left, from: visible, landscape, to: leftDisplay, landscape).width == 200)
    }

    @Test func upAndDownLandAgainstTheBottomOrTopEdge() {
        let above = Rect(x: 100, y: 650, width: 1200, height: 600)
        let window = Rect(x: 400, y: 450, width: 300, height: 200)
        let up = Geometry.carry(window, .up, from: visible, landscape, to: above, landscape)
        #expect(up == Rect(x: 400, y: 650, width: 300, height: 200))
        let down = Geometry.carry(up, .down, from: above, landscape, to: visible, landscape)
        #expect(down == Rect(x: 400, y: 450, width: 300, height: 200))
    }
}

@Suite struct SameFrame {
    @Test func withinOnePointOnEveryEdgeIsTheSame() {
        let a = Rect(x: 100, y: 50, width: 600, height: 600)
        #expect(Geometry.sameFrame(a, a))
        #expect(Geometry.sameFrame(a, Rect(x: 100.5, y: 49.5, width: 600, height: 601)))
        // Exactly one point off on an edge still counts.
        #expect(Geometry.sameFrame(a, Rect(x: 101, y: 50, width: 599, height: 600)))
    }

    @Test func moreThanOnePointOnAnyEdgeDiffers() {
        let a = Rect(x: 100, y: 50, width: 600, height: 600)
        #expect(!Geometry.sameFrame(a, Rect(x: 102, y: 50, width: 598, height: 600)))
        #expect(!Geometry.sameFrame(a, Rect(x: 100, y: 50, width: 602, height: 600)))
        #expect(!Geometry.sameFrame(a, Rect(x: 100, y: 50, width: 600, height: 598)))
        // The same size shifted by two points is a different frame.
        #expect(!Geometry.sameFrame(a, Rect(x: 102, y: 50, width: 600, height: 600)))
    }

    @Test func aHalfByHotkeyIsTheSameFrameAsAHalfOnTheGrid() throws {
        let odd = Rect(x: 1920, y: 300, width: 1601, height: 905)
        let half = try #require(Geometry.frame(for: .leftHalf, in: odd))
        let cells = Geometry.gridFrame(from: GridCell(column: 0, row: 0), to: GridCell(column: 5, row: 5), columns: 12, rows: 6, in: odd)
        #expect(Geometry.sameFrame(half, cells))
    }
}
