import AppKit
import CryptoKit
import Foundation

/// Standalone synthetic calibration. It never launches Kelpie or reads browser pixels.
@main struct ScriptVideoCalibration {
    private static let width = 640, height = 496, limit = 8 * 1024 * 1024
    private static let roi = CGRect(x: 432, y: 200, width: 97, height: 97)

    struct Fixture {
        let image: CGImage
        let roiSHA256: String
    }

    @MainActor static func fixture(offset: Int) throws -> Fixture {
        guard let graphics = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ScriptCaptureError.image }
        graphics.setFillColor(CGColor(gray: 1, alpha: 1))
        graphics.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Frozen pointer-shaped synthetic mark. Its differing version stays within the ROI.
        graphics.setFillColor(CGColor(gray: 0, alpha: 1))
        graphics.move(to: CGPoint(x: CGFloat(480 + offset), y: 248))
        graphics.addLine(to: CGPoint(x: CGFloat(484 + offset), y: 234))
        graphics.addLine(to: CGPoint(x: CGFloat(489 + offset), y: 239))
        graphics.addLine(to: CGPoint(x: CGFloat(494 + offset), y: 241))
        graphics.closePath()
        graphics.fillPath()
        guard let base = graphics.data, let image = graphics.makeImage() else { throw ScriptCaptureError.image }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var cropped = Data(capacity: Int(roi.width * roi.height) * 4)
        for row in Int(roi.minY)..<Int(roi.maxY) {
            cropped.append(bytes.advanced(by: (row * width + Int(roi.minX)) * 4), count: Int(roi.width) * 4)
        }
        let hash = SHA256.hash(data: cropped).map { String(format: "%02x", $0) }.joined()
        return Fixture(image: image, roiSHA256: hash)
    }

    @MainActor static func runCase(
        directory: URL,
        name: String,
        stable: Fixture,
        alternate: Fixture?,
        budget: ScriptCaptureBudget
    ) async throws -> [String: Any] {
        let url = directory.appendingPathComponent(name + ".mp4")
        let writer = try ScriptVideoWriter(url: url, width: width, height: height, budget: budget)
        var accepted: [[String: Any]] = []
        var rejected = 0
        for index in 0..<40 {
            let chosen = (index / 5).isMultiple(of: 2) ? stable : (alternate ?? stable)
            let tick = (index + 1) * 30 // Exact 20 fps in the writer's 1/600 time base.
            if try writer.append(chosen.image, seconds: Double(tick) / 600) {
                accepted.append(["tick": tick, "sourceROIHash": chosen.roiSHA256])
            } else {
                rejected += 1
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard accepted.count >= 16, let last = accepted.last?["tick"] as? Int else {
            throw ScriptCaptureError.image
        }
        let finished = try await writer.finish(endSeconds: Double(last + 30) / 600)
        let size = try finished.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard !writer.budgetExceeded, writer.rejectedFrameCount == 0,
              writer.encodedFrameCount == accepted.count, size > 0, size <= limit else {
            throw ScriptCaptureError.image
        }
        return ["name": name, "file": finished.lastPathComponent, "size": size,
                "accepted": accepted, "appendRejected": rejected, "encodedFrames": writer.encodedFrameCount]
    }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw ScriptCaptureError.image }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw ScriptCaptureError.image }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let first = try fixture(offset: 0), shifted = try fixture(offset: 8)
        guard first.roiSHA256 != shifted.roiSHA256 else { throw ScriptCaptureError.image }
        let budget = ScriptCaptureBudget(directory: directory, maximumBytes: limit)
        let stable = try await runCase(directory: directory, name: "stable", stable: first, alternate: nil, budget: budget)
        let varying = try await runCase(directory: directory, name: "varying", stable: first, alternate: shifted, budget: budget)
        let manifest: [String: Any] = ["version": 1, "width": width, "height": height,
                                       "roi": [432, 200, 97, 97], "timeBase": "1/600", "cases": [stable, varying]]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        guard data.count <= 32768 else { throw ScriptCaptureError.image }
        try data.write(to: directory.appendingPathComponent("input.json"), options: .withoutOverwriting)
    }
}
