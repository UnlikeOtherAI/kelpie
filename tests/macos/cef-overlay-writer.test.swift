import AppKit

@main struct Main {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-writer-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("discard.mp4")
        let budget = ScriptCaptureBudget(directory: directory, maximumBytes: 2 * 1024 * 1024)
        let writer = try ScriptVideoWriter(url: path, width: 64, height: 64, budget: budget)
        guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let frame = context.makeImage() else { fatalError("fixture") }
        _ = try writer.append(frame, seconds: 0.1)
        writer.discard()
        guard !FileManager.default.fileExists(atPath: path.path) else { fatalError("discard left an artifact") }
        print("PASS: real native writer discards unpublished output")
    }
}
