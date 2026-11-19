import CoreFoundation
import Foundation

struct TapMarkerOptions {
    enum Style: String {
        case circle
        case crosshairCoordinates = "crosshair-coordinates"
    }

    static let defaults = Self(style: .circle, durationMs: 550)
    static let invalidMessage = "marker must contain only a supported style and/or an integer durationMs from 0 to 2147483647"

    let style: Style
    let durationMs: Int

    static func parse(_ value: Any?) -> Self? {
        guard let value else { return defaults }
        guard let marker = value as? [String: Any],
              marker.keys.allSatisfy({ $0 == "style" || $0 == "durationMs" })
        else { return nil }

        var style = defaults.style
        if let raw = marker["style"] {
            guard let name = raw as? String, let parsed = Style(rawValue: name) else { return nil }
            style = parsed
        }
        var duration = defaults.durationMs
        if let raw = marker["durationMs"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let parsed = Int(exactly: number.doubleValue), (0...Int(Int32.max)).contains(parsed)
            else { return nil }
            duration = parsed
        }
        return Self(style: style, durationMs: duration)
    }

    private static let source: String? = {
        guard let url = KelpieResources.bundle.url(forResource: "tap-marker", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    func script(x: Double, y: Double, rgb: String) -> String? {
        guard let source = Self.source else { return nil }
        return "(\(source))(\(x), \(y), '\(JSEscape.string(rgb))', '\(style.rawValue)', \(durationMs));"
    }
}
