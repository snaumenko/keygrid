import Testing
@testable import KeyGridCore

private func rect(_ n: Double) -> Rect { Rect(x: n, y: n, width: 100, height: 100) }

@Suite struct RememberingFrames {
    @Test func takeReturnsWhatWasRememberedOnce() {
        var memory = FrameMemory<Int, Rect>()
        memory.remember(rect(1), for: 7)
        #expect(memory.take(for: 7) == rect(1))
        // Taken means forgotten.
        #expect(memory.take(for: 7) == nil)
        #expect(memory.count == 0)
    }

    @Test func peekReadsWithoutForgetting() {
        var memory = FrameMemory<Int, Rect>()
        memory.remember(rect(1), for: 7)
        #expect(memory.peek(for: 7) == rect(1))
        #expect(memory.peek(for: 7) == rect(1))
        #expect(memory.peek(for: 8) == nil)
        #expect(memory.count == 1)
    }

    @Test func unknownKeyGivesNil() {
        var memory = FrameMemory<Int, Rect>()
        memory.remember(rect(1), for: 7)
        #expect(memory.take(for: 8) == nil)
        #expect(memory.count == 1)
    }

    @Test func rememberingAgainReplacesTheFrame() {
        var memory = FrameMemory<Int, Rect>()
        memory.remember(rect(1), for: 7)
        memory.remember(rect(2), for: 7)
        #expect(memory.count == 1)
        #expect(memory.take(for: 7) == rect(2))
    }

    @Test func theOldestEntryIsDroppedPastTheCapacity() {
        var memory = FrameMemory<Int, Rect>(capacity: 2)
        memory.remember(rect(1), for: 1)
        memory.remember(rect(2), for: 2)
        memory.remember(rect(3), for: 3)
        #expect(memory.count == 2)
        #expect(memory.take(for: 1) == nil)
        #expect(memory.take(for: 2) == rect(2))
        #expect(memory.take(for: 3) == rect(3))
    }

    @Test func rememberingAgainMakesTheEntryNewest() {
        // Key 1 is refreshed after key 2, so key 2 is the oldest and goes.
        var memory = FrameMemory<Int, Rect>(capacity: 2)
        memory.remember(rect(1), for: 1)
        memory.remember(rect(2), for: 2)
        memory.remember(rect(11), for: 1)
        memory.remember(rect(3), for: 3)
        #expect(memory.take(for: 2) == nil)
        #expect(memory.take(for: 1) == rect(11))
    }

    @Test func defaultCapacityIsThirtyTwo() {
        #expect(FrameMemory<Int, Rect>().capacity == 32)
    }
}
