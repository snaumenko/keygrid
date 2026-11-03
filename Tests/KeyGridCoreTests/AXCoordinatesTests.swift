import Testing
@testable import KeyGridCore

// A 1920 × 1200 primary display. Its full frame height is the pivot; the
// menu bar and Dock shrink the visible frame but move neither origin.
private let primaryHeight = 1200.0

@Suite struct AXConversion {
    @Test func windowOnThePrimaryDisplay() {
        // Bottom edge 200 above the AppKit origin, 600 tall, so its top edge
        // is 800 above the bottom and 1200 - 800 = 400 below the top.
        let appKit = Rect(x: 100, y: 200, width: 800, height: 600)
        let ax = Rect(x: 100, y: 400, width: 800, height: 600)
        #expect(AXCoordinates.toAX(appKit, primaryHeight: primaryHeight) == ax)
        #expect(AXCoordinates.fromAX(ax, primaryHeight: primaryHeight) == appKit)
    }

    @Test func fullPrimaryDisplayIsZeroInBoth() {
        let display = Rect(x: 0, y: 0, width: 1920, height: 1200)
        #expect(AXCoordinates.toAX(display, primaryHeight: primaryHeight) == display)
    }

    // A display stacked above the primary. In AppKit its frames start at
    // y = 1200 (the primary's top edge) and go up; the Accessibility API
    // reports them with negative y, since they sit above its origin.
    @Test func displayAboveThePrimary() {
        // 300 points above the primary's top edge.
        let appKit = Rect(x: 0, y: 1200 + 300, width: 800, height: 500)
        // Top edge is 2000 above the AppKit origin: 1200 - 2000 = -800.
        let ax = Rect(x: 0, y: -800, width: 800, height: 500)
        #expect(AXCoordinates.toAX(appKit, primaryHeight: primaryHeight) == ax)
        #expect(AXCoordinates.fromAX(ax, primaryHeight: primaryHeight) == appKit)
    }

    // A display below the primary: AppKit y is negative, AX y is past the
    // primary's height.
    @Test func displayBelowThePrimary() {
        let appKit = Rect(x: 300, y: -900, width: 400, height: 300)
        // Top edge is -600: 1200 - (-600) = 1800.
        let ax = Rect(x: 300, y: 1800, width: 400, height: 300)
        #expect(AXCoordinates.toAX(appKit, primaryHeight: primaryHeight) == ax)
        #expect(AXCoordinates.fromAX(ax, primaryHeight: primaryHeight) == appKit)
    }

    @Test(arguments: [
        Rect(x: 0, y: 0, width: 1, height: 1),
        Rect(x: -1920, y: -300, width: 1920, height: 1080),
        Rect(x: 2560, y: 1500, width: 1200, height: 800),
        Rect(x: 100.5, y: 200.25, width: 800.75, height: 600.125),
    ])
    func roundTripIsExact(_ rect: Rect) {
        let there = AXCoordinates.toAX(rect, primaryHeight: primaryHeight)
        #expect(AXCoordinates.fromAX(there, primaryHeight: primaryHeight) == rect)
        #expect(AXCoordinates.toAX(AXCoordinates.fromAX(rect, primaryHeight: primaryHeight),
                                   primaryHeight: primaryHeight) == rect)
    }

    @Test func onlyYChanges() {
        let rect = Rect(x: 123, y: 456, width: 789, height: 12)
        let ax = AXCoordinates.toAX(rect, primaryHeight: primaryHeight)
        #expect(ax.x == rect.x && ax.width == rect.width && ax.height == rect.height)
        #expect(ax.y != rect.y)
    }
}
