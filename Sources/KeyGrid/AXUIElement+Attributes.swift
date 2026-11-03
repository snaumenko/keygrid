import ApplicationServices

/// Small typed readers and writers over the C-style
/// `AXUIElementCopyAttributeValue` and `AXUIElementSetAttributeValue`, so
/// `DockSwitcher` and `WindowMover` can say `element.title` or
/// `window.frame` instead of juggling `CFTypeRef` and `AXError` at every
/// step.
///
/// An `AXUIElement` is the Accessibility API's handle on one piece of
/// another app's user interface: the app itself, a window, a Dock icon.
/// Reading an attribute can fail with an `AXError`. The statuses this
/// program acts on are `.apiDisabled` (the Accessibility permission is
/// not granted) and `.noValue` (the attribute exists but has nothing right
/// now, for example an app with no focused window); every other status is
/// logged by name. Nothing here decides what a failure means; the callers
/// do, because one status is a bug in one place and a normal absence in
/// another.
extension AXUIElement {
    /// The raw read, keeping the `AXError` status. Used where the status
    /// matters: an app's top-level element, where a permission denial shows
    /// up as `.apiDisabled`.
    func copyAttribute(_ name: String) -> (value: CFTypeRef?, status: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return (value, status)
    }

    /// Convenience for leaf attributes, where absence is normal (a Dock
    /// separator has no title). Returns nil when the attribute is missing,
    /// of another type, or unreadable.
    func attribute(_ name: String) -> CFTypeRef? {
        let read = copyAttribute(name)
        return read.status == .success ? read.value : nil
    }

    var role: String? { attribute(kAXRoleAttribute) as? String }
    var subrole: String? { attribute(kAXSubroleAttribute) as? String }
    var title: String? { attribute(kAXTitleAttribute) as? String }
    var url: URL? { attribute(kAXURLAttribute) as? URL }
    var children: [AXUIElement]? { attribute(kAXChildrenAttribute) as? [AXUIElement] }
    /// On an application's top-level element: whether that app is the
    /// active one right now, as the app itself reports it. Nil when it
    /// could not be read.
    var isFrontmost: Bool? { attribute(kAXFrontmostAttribute) as? Bool }

    /// A window's position, in Accessibility coordinates (top-left origin,
    /// see "Coordinate systems" in `docs/ARCHITECTURE.md`), with the
    /// `AXError` status of the read. The value is nil when the status is not
    /// `.success`. When the read succeeded but the app returned something
    /// that is not an `AXValue` holding a `CGPoint`, the value is nil and
    /// the status is `.failure`. Apple's `AXError.h` defines `.failure` as a
    /// generic system error (for example a failed allocation); this program
    /// treats a wrong-typed value the same way, so the two share one status
    /// and one log word.
    var position: (value: CGPoint?, status: AXError) {
        let read = copyAttribute(kAXPositionAttribute)
        guard read.status == .success else { return (nil, read.status) }
        var point = CGPoint.zero
        guard let value = read.value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return (nil, .failure) }
        return (point, .success)
    }

    /// A window's size in points, with the `AXError` status of the read.
    /// The value is nil when the status is not `.success`. A nil value with
    /// `.failure` status means the read succeeded but the app returned
    /// something that is not an `AXValue` holding a `CGSize`.
    var size: (value: CGSize?, status: AXError) {
        let read = copyAttribute(kAXSizeAttribute)
        guard read.status == .success else { return (nil, read.status) }
        var size = CGSize.zero
        guard let value = read.value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgSize, &size) else { return (nil, .failure) }
        return (size, .success)
    }

    /// Writes a window's position, in Accessibility coordinates. Returns the
    /// API's status; `.success` means the app accepted the write, not that
    /// the window landed exactly there.
    func setPosition(_ point: CGPoint) -> AXError {
        var point = point
        // AXValueCreate returns nil only for an unknown AXValueType or a null
        // pointer; both are fixed here, so the unwrap cannot fail.
        let value = AXValueCreate(.cgPoint, &point)!
        return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
    }

    /// Writes a window's size. Returns the API's status; a window with a
    /// minimum size or a fixed aspect ratio may accept the write and keep a
    /// different size.
    func setSize(_ size: CGSize) -> AXError {
        var size = size
        // AXValueCreate returns nil only for an unknown AXValueType or a null
        // pointer; both are fixed here, so the unwrap cannot fail.
        let value = AXValueCreate(.cgSize, &size)!
        return AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value)
    }
}

extension AXError {
    /// The status as a word for the log, from the `AXError` enum in Apple's
    /// `AXError.h`, so a reader does not have to look up `-25204`. Codes not
    /// named here print as their number.
    var name: String {
        switch self {
        case .success:                return "success"
        case .failure:                return "failure (a system error, or a value of the wrong type)"
        case .illegalArgument:        return "illegalArgument"
        case .invalidUIElement:       return "invalidUIElement (the app or window is gone)"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete:         return "cannotComplete (the app is not responding)"
        case .attributeUnsupported:   return "attributeUnsupported"
        case .actionUnsupported:      return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented:         return "notImplemented (the app has no accessibility support)"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled:            return "apiDisabled (Accessibility permission is not granted)"
        case .noValue:                return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:     return "notEnoughPrecision"
        @unknown default:             return "AXError \(rawValue)"
        }
    }
}
