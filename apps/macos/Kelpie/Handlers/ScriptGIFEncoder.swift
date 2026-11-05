import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO owns only one frame at a time. This writer streams palettes and LZW blocks into the animation.
enum ScriptGIFEncoder {
    struct Result {
        let frameCount: Int
        let durationMs: Int
        let partial: Bool
    }

    static func encode(
        frames: [(URL, Double)],
        fps: Int,
        endSeconds: Double,
        to url: URL,
        budget: ScriptCaptureBudget,
        shouldContinue: @Sendable () -> Bool = { true }
    ) throws -> Result {
        guard !frames.isEmpty, (1...30).contains(fps), endSeconds.isFinite else { throw ScriptCaptureError.image }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-gif-frame-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let frameBudget = ScriptCaptureBudget(directory: scratch, maximumBytes: 16 * 1024 * 1024)
        let output = try budget.output(url: url)
        var count = 0
        var elapsedCentiseconds = 0
        var dimensions: (Int, Int)?
        var previousTime = -Double.infinity
        var partial = false
        do {
            for (index, frame) in frames.enumerated() {
                if !shouldContinue() {
                    guard count > 0 else { throw ScriptCaptureError.cancelled }
                    partial = true
                    break
                }
                guard frame.1.isFinite, frame.1 >= 0, frame.1 > previousTime else { throw ScriptCaptureError.image }
                previousTime = frame.1
                let staged = scratch.appendingPathComponent("frame.gif")
                let geometry = try autoreleasepool {
                    try singleFrame(frame.0, to: staged, budget: frameBudget)
                }
                defer { try? FileManager.default.removeItem(at: staged) }
                if let dimensions {
                    guard dimensions.0 == geometry.0, dimensions.1 == geometry.1 else { throw ScriptCaptureError.viewport }
                } else { dimensions = geometry }
                let encoded = try Frame(url: staged, expected: geometry)
                defer { try? encoded.close() }
                let next = index + 1 < frames.count ? frames[index + 1].1 : max(endSeconds, frame.1 + 1 / Double(fps))
                let desired = (next - frames[0].1) * 100
                guard desired.isFinite, desired >= 0, desired <= 31000 else { throw ScriptCaptureError.duration }
                let delay = max(Int(desired.rounded()) - elapsedCentiseconds, 2)
                guard delay <= 65535 else { throw ScriptCaptureError.duration }
                // Pre-admit the complete frame plus the trailer; no partially appended frame on budget exhaustion.
                let headerBytes = count == 0 ? 32 : 0
                do { try budget.check(headroom: headerBytes + 8 + encoded.payloadBytes + 1) } catch ScriptCaptureError.budget {
                    guard count > 0 else { throw ScriptCaptureError.budget }
                    partial = true
                    break
                }
                if count == 0 {
                    var header = Data("GIF89a".utf8)
                    header.append(contentsOf: littleEndian(geometry.0) + littleEndian(geometry.1) + [0x70, 0, 0])
                    header.append(contentsOf: [0x21, 0xFF, 0x0B])
                    header.append(Data("NETSCAPE2.0".utf8))
                    header.append(contentsOf: [3, 1, 0, 0, 0])
                    try output.write(header)
                }
                try output.write(Data([0x21, 0xF9, 4, 4 | encoded.transparencyFlag] +
                                      littleEndian(delay) + [encoded.transparentIndex, 0]))
                try encoded.copyImage(to: output)
                elapsedCentiseconds += delay
                count += 1
            }
            guard count > 0 else { throw ScriptCaptureError.image }
            try output.write(Data([0x3B]))
            try output.close()
            try budget.check()
            return Result(frameCount: count, durationMs: elapsedCentiseconds * 10, partial: partial)
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func singleFrame(_ sourceURL: URL, to url: URL, budget: ScriptCaptureBudget) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...1920).contains(width), (1...1920).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw ScriptCaptureError.image
        }
        try budget.withConsumer(url: url) { consumer in
            guard let destination = CGImageDestinationCreateWithDataConsumer(consumer, UTType.gif.identifier as CFString, 1, nil) else {
                throw ScriptCaptureError.image
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ScriptCaptureError.budget }
        }
        return (width, height)
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [UInt8(value & 255), UInt8((value >> 8) & 255)]
    }

    private final class Frame {
        private let handle: FileHandle
        private let imageOffset: UInt64
        private let descriptor: Data
        private let palette: Data
        private let blocksOffset: UInt64
        let payloadBytes: Int
        let transparencyFlag: UInt8
        let transparentIndex: UInt8

        init(url: URL, expected: (Int, Int)) throws {
            handle = try FileHandle(forReadingFrom: url)
            let header = try Self.read(handle, count: 13)
            guard ["GIF87a", "GIF89a"].contains(String(bytes: header.prefix(6), encoding: .ascii) ?? ""),
                  Self.word(header, 6) == expected.0, Self.word(header, 8) == expected.1 else { throw ScriptCaptureError.image }
            let global = header[10] & 0x80 != 0 ? try Self.read(handle, count: 3 << (Int(header[10] & 7) + 1)) : Data()
            var transparency: UInt8 = 0
            var transparent: UInt8 = 0
            var foundDescriptor = Data()
            var foundPalette = Data()
            var foundOffset: UInt64 = 0
            var foundBlocks: UInt64 = 0
            while true {
                let tag = try Self.read(handle, count: 1)[0]
                if tag == 0x21 {
                    let label = try Self.read(handle, count: 1)[0]
                    if label == 0xF9 {
                        let control = try Self.read(handle, count: 6)
                        guard control[0] == 4, control[5] == 0 else { throw ScriptCaptureError.image }
                        transparency = control[1] & 1
                        transparent = control[4]
                    } else { try Self.skipBlocks(handle) }
                } else if tag == 0x2C {
                    foundOffset = try handle.offset() - 1
                    var image = Data([tag])
                    image.append(try Self.read(handle, count: 9))
                    guard Self.word(image, 1) == 0, Self.word(image, 3) == 0,
                          Self.word(image, 5) == expected.0, Self.word(image, 7) == expected.1 else { throw ScriptCaptureError.image }
                    let packed = image[9]
                    if packed & 0x80 != 0 {
                        foundPalette = try Self.read(handle, count: 3 << (Int(packed & 7) + 1))
                    } else {
                        guard !global.isEmpty else { throw ScriptCaptureError.image }
                        foundPalette = global
                        image[9] = (packed & 0x78) | 0x80 | (header[10] & 7)
                    }
                    foundDescriptor = image
                    foundBlocks = try handle.offset()
                    _ = try Self.read(handle, count: 1) // LZW minimum code size.
                    try Self.skipBlocks(handle)
                    guard try Self.read(handle, count: 1)[0] == 0x3B else { throw ScriptCaptureError.image }
                    break
                } else { throw ScriptCaptureError.image }
            }
            imageOffset = foundOffset
            descriptor = foundDescriptor
            palette = foundPalette
            blocksOffset = foundBlocks
            let end = try handle.offset() - 1
            payloadBytes = descriptor.count + palette.count + Int(end - foundBlocks)
            transparencyFlag = transparency
            transparentIndex = transparent
        }

        func close() throws { try handle.close() }
        deinit { try? handle.close() }

        func copyImage(to output: ScriptCaptureBudget.Output) throws {
            guard imageOffset >= 13 else { throw ScriptCaptureError.image }
            try output.write(descriptor)
            try output.write(palette)
            try handle.seek(toOffset: blocksOffset)
            try output.write(Self.read(handle, count: 1))
            while true {
                let length = try Self.read(handle, count: 1)[0]
                try output.write(Data([length]))
                if length == 0 { break }
                try output.write(Self.read(handle, count: Int(length)))
            }
        }

        private static func word(_ data: Data, _ offset: Int) -> Int { Int(data[offset]) | (Int(data[offset + 1]) << 8) }
        private static func read(_ handle: FileHandle, count: Int) throws -> Data {
            guard let data = try handle.read(upToCount: count), data.count == count else { throw ScriptCaptureError.image }
            return data
        }
        private static func skipBlocks(_ handle: FileHandle) throws {
            var total = 0
            while true {
                let size = Int(try read(handle, count: 1)[0])
                if size == 0 { return }
                total += size
                guard total <= 16 * 1024 * 1024 else { throw ScriptCaptureError.image }
                _ = try read(handle, count: size)
            }
        }
    }
}
