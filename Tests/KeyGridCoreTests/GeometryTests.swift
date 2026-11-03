import Testing
@testable import KeyGridCore

// A second display to the right of and above the primary, with the menu
// bar and Dock taken off: an origin that is not zero on either axis, and
// odd width and height so halves do not fall on whole points.
private let visible = Rect(x: 1920, y: 300, width: 1601, height: 905)

// The same display placed left of and below the primary, so every
// coordinate is negative. Swift's `Double.rounded()`, which Geometry uses,
// rounds halves away from zero, which mirrors the split (-800.5 becomes
// -801), and tiling must still hold.
private let negativeVisible = Rect(x: -1601, y: -200, width: 1601, height: 905)

@Suite struct Placements {
    @Test func fullIsTheVisibleFrame() {
        #expect(Geometry.frame(for: .full, in: visible) == visible)
    }

    @Test func halves() {
        // Half of 1601 is 800.5; the shared edge rounds to 1920 + 801 = 2721.
        #expect(Geometry.frame(for: .leftHalf, in: visible) == Rect(x: 1920, y: 300, width: 801, height: 905))
        #expect(Geometry.frame(for: .rightHalf, in: visible) == Rect(x: 2721, y: 300, width: 800, height: 905))
    }

    // The halves share their edge with the 12×6 grid's middle line, so a
    // half placed by hotkey and a half dragged on the grid are the same frame.
    @Test func halvesMatchTheGridsMiddleLine() throws {
        let left = try #require(Geometry.frame(for: .leftHalf, in: visible))
        let cells = Geometry.gridFrame(from: GridCell(column: 0, row: 0), to: GridCell(column: 5, row: 5), columns: 12, rows: 6, in: visible)
        #expect(left == cells)
    }

    // Neighbouring placements share an edge and together cover the frame.
    @Test(arguments: [visible, negativeVisible])
    func halvesTileWithoutGapOrOverlap(_ display: Rect) throws {
        let left = try #require(Geometry.frame(for: .leftHalf, in: display))
        let right = try #require(Geometry.frame(for: .rightHalf, in: display))
        #expect(left.maxX == right.minX)
        #expect(left.minX == display.minX && right.maxX == display.maxX)
        #expect(left.width + right.width == display.width)
    }

    @Test(arguments: [WindowAction.sweepLeft, .sweepRight, .sweepUp, .sweepDown])
    func aSweepIsNotAPlacement(_ action: WindowAction) {
        #expect(action.sweepDirection != nil && action.moveDirection == nil)
        #expect(Geometry.frame(for: action, in: visible) == nil)
    }

    @Test func onlyTheHalvesCarryOnASecondPress() {
        #expect(WindowAction.leftHalf.carryDirection == .left && WindowAction.leftHalf.oppositeHalf == .rightHalf)
        #expect(WindowAction.rightHalf.carryDirection == .right && WindowAction.rightHalf.oppositeHalf == .leftHalf)
        for action in WindowAction.allCases where action != .leftHalf && action != .rightHalf {
            #expect(action.carryDirection == nil && action.oppositeHalf == nil, "\(action)")
        }
    }

    // The landing on the next display is a half of that display, whatever
    // its shape: on a portrait display it is still half the width.
    @Test func theOppositeHalfIsAHalfOfAnyDisplay() throws {
        let portrait = Rect(x: -1080, y: 0, width: 1080, height: 1920)
        let landed = try #require(Geometry.frame(for: WindowAction.leftHalf.oppositeHalf!, in: portrait))
        #expect(landed == Rect(x: -540, y: 0, width: 540, height: 1920))
    }

    @Test func centerTwoThirdsLeavesEqualGapsOnAllSides() throws {
        // Shorter edge 905; the gap is 905 / 6 = 150.83 on every side.
        let frame = try #require(Geometry.frame(for: .centerTwoThirds, in: visible))
        #expect(frame.minX - visible.minX == visible.maxX - frame.maxX)
        #expect(frame.minY - visible.minY == visible.maxY - frame.maxY)
        #expect(frame.minX - visible.minX == frame.minY - visible.minY)
        // 1920 + 150.83 = 2070.83 → 2071; 3521 - 150.83 = 3370.17 → 3370;
        // 300 + 150.83 → 451; 1205 - 150.83 → 1054.
        #expect(frame == Rect(x: 2071, y: 451, width: 1299, height: 603))
        // On the default grid a row is one sixth of the height, so the top
        // and bottom edges are the grid's row lines 1 and 5.
        let rows = Geometry.gridFrame(from: GridCell(column: 0, row: 1), to: GridCell(column: 11, row: 4), columns: 12, rows: 6, in: visible)
        #expect(frame.minY == rows.minY && frame.maxY == rows.maxY)
    }

    @Test func aHalfPointGapIsRoundedOnceSoAllFourGapsMatch() throws {
        // A 14-inch MacBook Pro with the Dock hidden: 1512 × 945 visible,
        // gap 945 / 6 = 157.5 → 158 on every side, not 158 and 157.
        let laptop = Rect(x: 0, y: 37, width: 1512, height: 945)
        let frame = try #require(Geometry.frame(for: .centerTwoThirds, in: laptop))
        #expect(frame == Rect(x: 158, y: 195, width: 1196, height: 629))
    }

    @Test func centerTwoThirdsOnAPortraitDisplayUsesTheWidth() throws {
        let portrait = Rect(x: 0, y: 0, width: 600, height: 1200)
        #expect(try #require(Geometry.frame(for: .centerTwoThirds, in: portrait)) == Rect(x: 100, y: 100, width: 400, height: 1000))
    }

    @Test func centerIsNotAPlacementFromTheDisplayAlone() {
        #expect(WindowAction.center.sweepDirection == nil && WindowAction.center.moveDirection == nil)
        #expect(Geometry.frame(for: .center, in: visible) == nil)
    }

    @Test func onlyTheDisplayJumpsHaveAStep() {
        #expect(WindowAction.previousDisplay.displayStep == -1)
        #expect(WindowAction.nextDisplay.displayStep == 1)
        for action in WindowAction.allCases where action.displayStep != nil {
            #expect(action.sweepDirection == nil && action.moveDirection == nil && action.carryDirection == nil)
            #expect(Geometry.frame(for: action, in: visible) == nil)
        }
        #expect(WindowAction.allCases.filter { $0.displayStep != nil }.count == 2)
    }

    @Test(arguments: [WindowAction.moveLeft, .moveRight, .moveUp, .moveDown])
    func aMoveIsNotAPlacement(_ action: WindowAction) {
        #expect(action.moveDirection != nil && action.sweepDirection == nil)
        #expect(Geometry.frame(for: action, in: visible) == nil)
    }

    @Test(arguments: WindowAction.allCases.filter { $0.sweepDirection == nil && $0.moveDirection == nil && $0.displayStep == nil && $0 != .center }, [visible, negativeVisible])
    func everyPlacementStaysInsideTheFrame(_ action: WindowAction, _ display: Rect) throws {
        let frame = try #require(Geometry.frame(for: action, in: display))
        #expect(frame.minX >= display.minX && frame.maxX <= display.maxX)
        #expect(frame.minY >= display.minY && frame.maxY <= display.maxY)
        #expect(frame.width > 0 && frame.height > 0)
    }
}

@Suite struct RectEdges {
    @Test func edgesAreDerivedFromOriginAndSize() {
        let rect = Rect(x: 10, y: 20, width: 30, height: 40)
        #expect(rect.minX == 10 && rect.maxX == 40)
        #expect(rect.minY == 20 && rect.maxY == 60)
    }
}

@Suite struct Centering {
    @Test func keepsTheSizeAndCentersOnTheVisibleFrame() {
        // Visible frame center: 1920 + 800.5 = 2720.5, 300 + 452.5 = 752.5.
        let window = Rect(x: 0, y: 0, width: 400, height: 300)
        let centered = Geometry.centered(window, in: visible)
        #expect(centered.width == 400 && centered.height == 300)
        // Left edge 2720.5 - 200 = 2520.5 → 2521; bottom 752.5 - 150 = 602.5 → 603.
        #expect(centered == Rect(x: 2521, y: 603, width: 400, height: 300))
    }

    @Test func anOddLeftoverPointGoesToOneSide() {
        // 1601 - 400 = 1201 points to split: 600.5 each; rounded away from
        // zero the left gap is 601 and the right 600.
        let window = Rect(x: 0, y: 0, width: 400, height: 905)
        let centered = Geometry.centered(window, in: visible)
        #expect(centered.minX - visible.minX == 601)
        #expect(visible.maxX - centered.maxX == 600)
    }

    @Test func aWindowLargerThanTheDisplayOverhangsEqually() {
        let window = Rect(x: 0, y: 0, width: 2001, height: 1105)
        let centered = Geometry.centered(window, in: visible)
        #expect(centered.width == 2001 && centered.height == 1105)
        #expect(visible.minX - centered.minX == 200 && centered.maxX - visible.maxX == 200)
        #expect(visible.minY - centered.minY == 100 && centered.maxY - visible.maxY == 100)
    }

    @Test func theSizeIsKeptAcrossCoordinateZero() {
        // A display left of the primary whose visible frame straddles x = 0
        // and y = 0: a fractional origin would round each edge away from
        // zero in opposite directions and grow the window by a point.
        let straddling = Rect(x: -301, y: -300, width: 1920, height: 1440)
        let window = Rect(x: 0, y: 0, width: 1501, height: 1301)
        let centered = Geometry.centered(window, in: straddling)
        #expect(centered.width == 1501 && centered.height == 1301)
        // Origin -301 + 209.5 = -91.5 → -92; -300 + 69.5 = -230.5 → -231.
        #expect(centered == Rect(x: -92, y: -231, width: 1501, height: 1301))
    }

    @Test func centeringTwiceIsTheSameFrame() {
        let once = Geometry.centered(Rect(x: 10, y: 10, width: 333, height: 222), in: visible)
        #expect(Geometry.centered(once, in: visible) == once)
    }
}

@Suite struct MovingBetweenDisplays {
    let primary = Rect(x: 0, y: 70, width: 1920, height: 1055)
    let secondary = Rect(x: 1920, y: 300, width: 1600, height: 875)

    // Moving a whole-point frame from a display to that same display must
    // hand it back untouched: the fractions round-trip exactly and the
    // clamp does not touch a window that already fits.
    @Test func sameDisplayLeavesTheFrameUnchanged() {
        let window = Rect(x: 100, y: 200, width: 800, height: 600)
        #expect(Geometry.frameMoving(window, from: primary, to: primary) == window)
    }

    // A fractional frame comes back on whole points; that is the contract,
    // not an exact round trip.
    @Test func fractionalFrameIsRoundedToWholePoints() {
        let window = Rect(x: 100.4, y: 200.3, width: 800, height: 600)
        #expect(Geometry.frameMoving(window, from: primary, to: primary)
                == Rect(x: 100, y: 200, width: 800, height: 600))
    }

    @Test func fractionsAreKept() throws {
        // Left half of the primary becomes left half of the secondary, also
        // for a destination left of and below the primary.
        let leftHalf = try #require(Geometry.frame(for: .leftHalf, in: primary))
        #expect(Geometry.frameMoving(leftHalf, from: primary, to: secondary)
                == Geometry.frame(for: .leftHalf, in: secondary))
        let negative = Rect(x: -1600, y: -500, width: 1600, height: 875)
        #expect(Geometry.frameMoving(leftHalf, from: primary, to: negative)
                == Geometry.frame(for: .leftHalf, in: negative))

        // A half-size window one quarter in from each edge stays there:
        // x 1920 + 0.25 × 1600 = 2320, width 800; y 300 + 0.25 × 875 = 518.75
        // → 519, top 300 + 0.75 × 875 = 956.25 → 956, so height 437.
        let window = Rect(x: 480, y: 70 + 263.75, width: 960, height: 527.5)
        #expect(Geometry.frameMoving(window, from: primary, to: secondary)
                == Rect(x: 2320, y: 519, width: 800, height: 437))
    }

    @Test func largerThanDestinationShrinksToFit() {
        let huge = Rect(x: -500, y: -500, width: 5000, height: 5000)
        #expect(Geometry.frameMoving(huge, from: primary, to: secondary) == secondary)
    }

    // Scaled width is 800 × 1600 / 1920 = 666.67 and height 400 × 875 / 1055
    // = 331.75 in the three hanging-off tests below; edges round to width 667 and
    // height 332.
    @Test func hangingOffTheRightIsShiftedInside() {
        // x 1920 + 1600 × (1520 / 1920) = 3186.67; right edge 3853.33 > 3520.
        let window = Rect(x: 1520, y: 70, width: 800, height: 400)
        #expect(Geometry.frameMoving(window, from: primary, to: secondary)
                == Rect(x: 2853, y: 300, width: 667, height: 332))
    }

    @Test func hangingOffTheLeftIsShiftedInside() {
        // x 1920 + 1600 × (-200 / 1920) = 1753.33 < 1920. y 300 + 875 × (130 / 1055) = 407.82.
        let window = Rect(x: -200, y: 200, width: 800, height: 400)
        #expect(Geometry.frameMoving(window, from: primary, to: secondary)
                == Rect(x: 1920, y: 408, width: 667, height: 332))
    }

    @Test func hangingOffTheTopIsShiftedInside() {
        // Top 1300 is past the primary's 1125; on the secondary the shift
        // puts the top at 1175, so y = 1175 - 331.75 = 843.25.
        let window = Rect(x: 100, y: 900, width: 800, height: 400)
        #expect(Geometry.frameMoving(window, from: primary, to: secondary)
                == Rect(x: 2003, y: 843, width: 667, height: 332))
    }

    @Test func tallerThanDestinationShrinksInHeightOnly() {
        // 1200 × 875 / 1055 = 995 > 875, so the height is clamped and the
        // bottom pinned; the width scales as usual.
        let window = Rect(x: 100, y: 0, width: 800, height: 1200)
        #expect(Geometry.frameMoving(window, from: primary, to: secondary)
                == Rect(x: 2003, y: 300, width: 667, height: 875))
    }

    @Test func zeroSizeSourceDoesNotDivideByZero() {
        let window = Rect(x: 10, y: 10, width: 100, height: 100)
        let degenerate = Rect(x: 0, y: 0, width: 0, height: 0)
        #expect(Geometry.frameMoving(window, from: degenerate, to: secondary) == secondary)
    }
}

@Suite struct DisplayOrder {
    @Test func leftToRightByLeftEdge() {
        // macOS lists the primary first; here it sits in the middle.
        let primary = Rect(x: 0, y: 0, width: 1920, height: 1080)
        let left = Rect(x: -1600, y: 100, width: 1600, height: 900)
        let right = Rect(x: 1920, y: -200, width: 2560, height: 1440)
        #expect(Geometry.displayOrder([primary, left, right]) == [1, 0, 2])
    }

    @Test func sameLeftEdgeGoesBottomToTop() {
        let lower = Rect(x: 0, y: 0, width: 1920, height: 1080)
        let upper = Rect(x: 0, y: 1080, width: 1920, height: 1080)
        #expect(Geometry.displayOrder([upper, lower]) == [1, 0])
    }

    @Test func identicalOriginsKeepTheirInputOrder() {
        let a = Rect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(Geometry.displayOrder([a, a, a]) == [0, 1, 2])
    }

    @Test func oneDisplayIsItself() {
        #expect(Geometry.displayOrder([Rect(x: 0, y: 0, width: 1, height: 1)]) == [0])
        #expect(Geometry.displayOrder([]) == [])
    }
}
