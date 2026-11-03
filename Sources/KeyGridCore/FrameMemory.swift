/// What windows looked like before `full` filled their display, so a
/// second ⌃⌥⏎ can put them back. A short list of (key, value) pairs,
/// newest first, with a fixed capacity; the oldest pair is dropped when
/// a new one would exceed it. In memory only: nothing here is written to
/// the config file or anywhere else, and the list is empty whenever the
/// app starts. It knows nothing about windows or displays; `WindowMover`
/// keys it by a window's Accessibility element and stores a
/// `FilledWindow`, the frames before and after the fill.
public struct FrameMemory<Key: Equatable, Value> {
    private var entries: [(key: Key, value: Value)] = []
    /// How many pairs are kept. 32 is far more windows than anyone fills
    /// and restores in one sitting, and four numbers each cost nothing.
    public let capacity: Int

    public init(capacity: Int = 32) {
        precondition(capacity >= 1, "a memory that holds nothing is a bug, not a setting")
        self.capacity = capacity
    }

    /// Stores `value` for `key`, replacing any value already stored for
    /// it, and makes it the newest entry. Drops the oldest entry if the
    /// list would otherwise grow past `capacity`.
    public mutating func remember(_ value: Value, for key: Key) {
        entries.removeAll { $0.key == key }
        entries.insert((key: key, value: value), at: 0)
        if entries.count > capacity {
            entries.removeLast()
        }
    }

    /// The value stored for `key`, left in place, or nil when none is.
    public func peek(for key: Key) -> Value? {
        entries.first { $0.key == key }?.value
    }

    /// Returns the value stored for `key` and forgets it, or nil when none
    /// is stored. Taking rather than reading means a restore uses the
    /// value once: the next fill remembers afresh.
    public mutating func take(for key: Key) -> Value? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        return entries.remove(at: index).value
    }

    /// How many values are stored, for tests.
    public var count: Int { entries.count }
}

/// One window's frames around a fill: `before`, where it was when ⌃⌥⏎
/// was pressed, to go back to; and `after`, the frame it actually took
/// once filled, which is the full frame for most windows and a few
/// points short for one that rounds its size to character cells or has
/// a maximum size. A window whose frame still matches `after` counts as
/// full, so the next ⌃⌥⏎ restores `before` instead of filling again.
public struct FilledWindow: Equatable, Sendable {
    public let before: Rect
    public let after: Rect

    public init(before: Rect, after: Rect) {
        self.before = before
        self.after = after
    }
}
