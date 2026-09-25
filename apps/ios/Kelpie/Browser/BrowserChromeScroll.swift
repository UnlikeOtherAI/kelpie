import CoreGraphics

/// Only finger movement changes chrome. WebKit can adjust content offsets during
/// deceleration or inset updates; those are not a new scrolling intention.
struct BrowserChromeScroll {
    private var anchor: CGFloat = 0

    mutating func update(translation: CGFloat, offset: CGFloat, maximum: CGFloat, userDragging: Bool) -> ScrollDirection? {
        guard userDragging, maximum > 24, offset >= 0, offset <= maximum else {
            anchor = translation
            return nil
        }
        let distance = translation - anchor
        guard abs(distance) > 18 else { return nil }
        anchor = translation
        return distance > 0 ? .down : .up
    }
}
