import CoreGraphics

/// Offset changes are not necessarily scrolling: layout, navigation and bounce
/// reset the baseline. Only a user's pan or its deceleration changes chrome.
struct BrowserChromeScroll {
    private var anchor: CGFloat?
    private var viewportHeight: CGFloat = 0

    mutating func update(offset: CGFloat, maximum: CGFloat, height: CGFloat, userScrolling: Bool) -> ScrollDirection? {
        guard userScrolling, maximum > 24, offset >= 0, offset <= maximum, height == viewportHeight else {
            anchor = offset
            viewportHeight = height
            return nil
        }
        guard let anchor else { self.anchor = offset; return nil }
        let distance = offset - anchor
        if offset <= 1 { self.anchor = offset; return .up }
        guard abs(distance) > 18 else { return nil }
        self.anchor = offset
        return distance > 0 ? .down : .up
    }
}
