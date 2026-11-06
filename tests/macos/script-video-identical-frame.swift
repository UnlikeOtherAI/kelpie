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
        let imageSHA256: String
    }

    @MainActor static func fixture(offset: Int, markerRadius: CGFloat = 0, markerAlpha: CGFloat = 0) throws -> Fixture {
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
        if markerRadius > 0 {
            graphics.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: markerAlpha))
            graphics.fillEllipse(in: CGRect(x: 480 - markerRadius, y: 248 - markerRadius,
                                            width: markerRadius * 2, height: markerRadius * 2))
        }
        guard let base = graphics.data, let image = graphics.makeImage() else { throw ScriptCaptureError.image }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var cropped = Data(capacity: Int(roi.width * roi.height) * 4)
        for row in Int(roi.minY)..<Int(roi.maxY) {
            cropped.append(bytes.advanced(by: (row * width + Int(roi.minX)) * 4), count: Int(roi.width) * 4)
        }
        let hash = SHA256.hash(data: cropped).map { String(format: "%02x", $0) }.joined()
        let full = Data(bytes: base, count: width * height * 4)
        let fullHash = SHA256.hash(data: full).map { String(format: "%02x", $0) }.joined()
        return Fixture(image: image, roiSHA256: hash, imageSHA256: fullHash)
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
            let useAlternate = alternate != nil && (name == "varying" ? !(index / 5).isMultiple(of: 2) : index < 20)
            let chosen = useAlternate ? alternate! : stable
            let tick = (index + 1) * 30 // Exact 20 fps in the writer's 1/600 time base.
            if try writer.append(chosen.image, seconds: Double(tick) / 600) {
                accepted.append(["tick": tick, "sourceROIHash": chosen.roiSHA256, "sourceImageHash": chosen.imageSHA256,
                                 "sourceKind": useAlternate ? "alternate" : "clean"])
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
        let smallFaint = try fixture(offset: 0, markerRadius: 3, markerAlpha: 0.02)
        let smallVisible = try fixture(offset: 0, markerRadius: 3, markerAlpha: 0.10)
        let mediumFaint = try fixture(offset: 0, markerRadius: 8, markerAlpha: 0.02)
        guard [shifted, smallFaint, smallVisible, mediumFaint].allSatisfy({ $0.roiSHA256 != first.roiSHA256 }) else {
            throw ScriptCaptureError.image
        }
        let budget = ScriptCaptureBudget(directory: directory, maximumBytes: limit)
        var cases: [[String: Any]] = []
        cases.append(try await runCase(directory: directory, name: "stable", stable: first, alternate: nil, budget: budget))
        cases.append(try await runCase(directory: directory, name: "varying", stable: first, alternate: shifted, budget: budget))
        cases.append(try await runCase(directory: directory, name: "holdout", stable: first, alternate: nil, budget: budget))
        cases.append(try await runCase(directory: directory, name: "small-faint", stable: first, alternate: smallFaint, budget: budget))
        cases.append(try await runCase(directory: directory, name: "small-visible", stable: first, alternate: smallVisible, budget: budget))
        cases.append(try await runCase(directory: directory, name: "medium-faint", stable: first, alternate: mediumFaint, budget: budget))
        let manifest: [String: Any] = ["version": 2, "width": width, "height": height,
            "roi": [432, 200, 97, 97], "timeBase": "1/600", "cases": cases,
            "cleanROIHash": first.roiSHA256, "varyingROIHash": shifted.roiSHA256,
            "cleanImageHash": first.imageSHA256, "varyingImageHash": shifted.imageSHA256,
            "markerControls": [
                ["name": "small-faint", "radiusPx": 3, "alpha": 0.02, "color": "#ff0000", "anchor": "pointer-tip", "sourceROIHash": smallFaint.roiSHA256, "sourceImageHash": smallFaint.imageSHA256],
                ["name": "small-visible", "radiusPx": 3, "alpha": 0.10, "color": "#ff0000", "anchor": "pointer-tip", "sourceROIHash": smallVisible.roiSHA256, "sourceImageHash": smallVisible.imageSHA256],
                ["name": "medium-faint", "radiusPx": 8, "alpha": 0.02, "color": "#ff0000", "anchor": "pointer-tip", "sourceROIHash": mediumFaint.roiSHA256, "sourceImageHash": mediumFaint.imageSHA256]
            ]]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        guard data.count <= 131072 else { throw ScriptCaptureError.image }
        try data.write(to: directory.appendingPathComponent("input.json"), options: .withoutOverwriting)
    }
}
