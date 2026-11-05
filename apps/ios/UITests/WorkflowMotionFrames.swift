import ImageIO
import XCTest

/// Independent image measurements on a neutral fixture. No product geometry or drawing helper is shared.
enum WorkflowMotionFrames {
    struct Sample {
        let time: Double
        let pointer: CGPoint?
        let indicatorWidth: Int
        let colorStrength: Int
    }

    static func decode(_ data: Data) throws -> [Sample] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        var elapsed = 0.0
        return try (0..<CGImageSourceGetCount(source)).map { index in
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            let duration = try XCTUnwrap((gif[kCGImagePropertyGIFUnclampedDelayTime as String] ??
                gif[kCGImagePropertyGIFDelayTime as String]) as? Double)
            defer { elapsed += duration }
            return try measure(image, time: elapsed)
        }
    }

    static func measure(_ image: CGImage, time: Double) throws -> Sample {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: 4 * width * height)
        return try rgba.withUnsafeMutableBytes { bytes in
            let graphics = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                   bitsPerComponent: 8, bytesPerRow: 4 * width,
                                                   space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            graphics.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var xSum = 0, ySum = 0, white = 0
            var left = width, right = -1, strength = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let red = Int(bytes[offset]), green = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
                let pixel = offset / 4, x = pixel % width
                if min(red, green, blue) > 220 {
                    white += 1
                    xSum += x
                    ySum += pixel / width
                }
                if red - green > 24, blue - green > 14 {
                    left = min(left, x)
                    right = max(right, x)
                    strength = max(strength, red - green)
                }
            }
            let pointer = white < 4 ? nil : CGPoint(x: Double(xSum) / Double(white), y: Double(ySum) / Double(white))
            return Sample(time: time, pointer: pointer, indicatorWidth: max(0, right - left + 1), colorStrength: strength)
        }
    }

    static func verify(_ frames: [Sample], curve: String) throws {
        let firstMarker = try XCTUnwrap(frames.firstIndex { $0.indicatorWidth > 0 })
        let travel = frames[..<firstMarker].filter { $0.pointer != nil }
        XCTAssertGreaterThanOrEqual(travel.count, 7, "Need enough admitted movie frames to measure pointer motion")
        let first = try XCTUnwrap(travel.first), origin = try XCTUnwrap(first.pointer)
        let end = try XCTUnwrap(frames.last?.pointer)
        let dx = end.x - origin.x, dy = end.y - origin.y
        let length = hypot(dx, dy)
        XCTAssertGreaterThan(length, 25)
        let duration = frames[firstMarker].time - first.time
        XCTAssertGreaterThan(duration, 1)
        var lateral: [Double] = []
        var early: [Double] = [], late: [Double] = []
        for sample in travel {
            let point = try XCTUnwrap(sample.pointer)
            let x = point.x - origin.x, y = point.y - origin.y
            let longitudinal = (x * dx + y * dy) / (length * length)
            lateral.append((-x * dy + y * dx) / (length * length))
            let elapsed = (sample.time - first.time) / duration
            if (0.12...0.32).contains(elapsed) { early.append(elapsed - longitudinal) }
            if (0.68...0.88).contains(elapsed) { late.append(longitudinal - elapsed) }
        }
        XCTAssertGreaterThan(try XCTUnwrap(early.max()), 0.025, "Ease-in should begin slower than a constant-speed pointer")
        XCTAssertGreaterThan(try XCTUnwrap(late.max()), 0.025, "Ease-out should approach its destination early")
        let left = -(lateral.min() ?? 0), right = lateral.max() ?? 0
        let marked = frames.filter { $0.indicatorWidth > 0 }
        let firstColor = try XCTUnwrap(marked.first)
        // Magenta #F000AA on neutral gray at the 0.7 baseline has an ideal
        // red-minus-green difference of 168; GIF palette quantization and a
        // first sampled fade frame may vary it slightly.
        XCTAssertGreaterThanOrEqual(firstColor.colorStrength, 145)
        XCTAssertLessThanOrEqual(firstColor.colorStrength, 180)
        if curve == "s" {
            XCTAssertGreaterThan(min(left, right), 0.018, "An S curve must pass on both sides of its chord")
            let strong = marked.filter { $0.colorStrength > 110 }
            let widths = strong.map(\.indicatorWidth)
            XCTAssertGreaterThan(try XCTUnwrap(widths.max()) - (widths.min() ?? 0), max(1, firstColor.indicatorWidth / 20))
            XCTAssertTrue(marked.contains { $0.colorStrength < firstColor.colorStrength / 2 })
        } else {
            XCTAssertGreaterThan(max(left, right), 0.07, "A C curve must visibly depart from its chord")
            XCTAssertLessThan(min(left, right), 0.025)
            XCTAssertTrue(marked.allSatisfy { abs($0.indicatorWidth - firstColor.indicatorWidth) <= 2 })
            XCTAssertTrue(marked.allSatisfy { abs($0.colorStrength - firstColor.colorStrength) <= 12 })
        }
        XCTAssertEqual(frames.last?.indicatorWidth, 0)
    }
}
