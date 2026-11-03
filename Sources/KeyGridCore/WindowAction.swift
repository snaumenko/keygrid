/// The fifteen things a window hotkey can do to the focused window: five
/// placements (fill the display, take its left half, take its right
/// half, center the window as it is, center it with equal gaps on all
/// sides), four sweeps (push one edge of the window towards the left,
/// right, top, or bottom of the display, one grid column or row at a
/// time; `Geometry.sweep` describes the rule), four moves (shift the
/// whole window one grid cell that way, onto the next display at the
/// edge; `Geometry.move` and `Geometry.carry` describe the rule), and
/// two display jumps (the whole window onto the previous or next
/// display in left-to-right order, keeping its place as fractions;
/// `Geometry.displayOrder` picks the display and `Geometry.frameMoving`
/// the frame). A half
/// placement on a window that already is that half puts it on the next
/// display on that side, as that display's near half.
///
/// This type is only a name list. The raw value of each case is both the
/// key under `"window"` in `config.json` and the suffix of the config
/// label (`window.leftHalf`) that error messages use. The default hotkey
/// for each action is in `Config`, a placement's frame is computed by
/// `Geometry.frame(for:in:)` (except `center`, whose frame keeps the
/// window's size and comes from `Geometry.centered(_:in:)`), a sweep's
/// by `Geometry.sweep`, a move's by `Geometry.move` or `Geometry.carry`,
/// a display jump's by `Geometry.frameMoving` on the display
/// `Geometry.displayOrder` picks, and the window is moved by
/// `WindowMover` in the app. Nothing here touches a
/// window or a display, and the JSON is not decoded into this enum:
/// `ConfigFile.Window` holds one optional string per case.
///
/// Declaration order is the order the actions appear in the default
/// config file and in `Config.allHotkeys`, so error text and log lines
/// list them the same way every time.
public enum WindowAction: String, CaseIterable, Sendable {
    case full
    case leftHalf
    case rightHalf
    case center
    case centerTwoThirds
    case sweepLeft
    case sweepRight
    case sweepUp
    case sweepDown
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case previousDisplay
    case nextDisplay

    /// How many displays along the left-to-right order a display jump
    /// goes: -1 for `previousDisplay`, +1 for `nextDisplay`, nil for every
    /// other action.
    public var displayStep: Int? {
        switch self {
        case .previousDisplay: return -1
        case .nextDisplay:     return 1
        default:               return nil
        }
    }

    /// The direction for a sweep action, nil for a placement, a move, or
    /// a display jump. `sweepDirection`, `moveDirection` and `displayStep`
    /// are how `WindowMover` tells the four kinds apart without a second
    /// list.
    public var sweepDirection: Direction? {
        switch self {
        case .full, .leftHalf, .rightHalf, .center, .centerTwoThirds, .moveLeft, .moveRight, .moveUp, .moveDown,
             .previousDisplay, .nextDisplay: return nil
        case .sweepLeft:  return .left
        case .sweepRight: return .right
        case .sweepUp:    return .up
        case .sweepDown:  return .down
        }
    }

    /// The side a half placement carries the window across when the window
    /// already is that half: `.left` for `leftHalf`, `.right` for
    /// `rightHalf`, nil for every other action (`full` included; issue 39
    /// is to give it a second-press meaning of its own).
    public var carryDirection: Direction? {
        switch self {
        case .leftHalf:  return .left
        case .rightHalf: return .right
        default:         return nil
        }
    }

    /// The half a window becomes when a half placement carries it onto the
    /// next display: the near half of that display, which is the opposite
    /// name. `rightHalf` for `leftHalf`, `leftHalf` for `rightHalf`, nil
    /// for every other action. A half, not a carry in grid cells: six of
    /// twelve columns is a half only on a 16:9 display, while
    /// `Geometry.frame(for:in:)` is a half on any display.
    public var oppositeHalf: WindowAction? {
        switch self {
        case .leftHalf:  return .rightHalf
        case .rightHalf: return .leftHalf
        default:         return nil
        }
    }

    /// The direction for a move action, nil for a placement, a sweep, or a
    /// display jump.
    public var moveDirection: Direction? {
        switch self {
        case .full, .leftHalf, .rightHalf, .center, .centerTwoThirds, .sweepLeft, .sweepRight, .sweepUp, .sweepDown,
             .previousDisplay, .nextDisplay: return nil
        case .moveLeft:  return .left
        case .moveRight: return .right
        case .moveUp:    return .up
        case .moveDown:  return .down
        }
    }
}
