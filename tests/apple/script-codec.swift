// Durable standalone Apple codec acceptance. See docs/plans/browser-automation-capture/macos.md.
import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO

func successResponse(_ values: [String: Any]) -> [String: Any] { values.merging(["success": true]) { _, new in new } }
func errorResponse(code: String, message: String) -> [String: Any] { ["success": false, "error": ["code": code, "message": message]] }

@main
struct ScriptCodecAcceptance {
    private final class ContinuationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        init(_ remaining: Int) { self.remaining = remaining }
        func proceed() -> Bool {
            lock.withLock {
                guard remaining > 0 else { return false }
                remaining -= 1
                return true
            }
        }
    }

    static func require(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !value() { throw NSError(domain: "ScriptCodecAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    }

    static func image(red: CGFloat, blue: CGFloat, width: Int = 160, height: Int = 90) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScriptCaptureError.image }
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ScriptCaptureError.image }
        return result
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func decodeGIF(_ url: URL, count: Int, duration: Double) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ScriptCaptureError.image }
        try require(CGImageSourceGetCount(source) == count, "GIF frame count")
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        try require((gif?[kCGImagePropertyGIFLoopCount] as? Int) == 0, "GIF infinite loop")
        var elapsed = 0.0
        for index in 0..<count {
            try autoreleasepool {
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                      let metadata = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
                      let delay = metadata[kCGImagePropertyGIFUnclampedDelayTime] as? Double ??
                          metadata[kCGImagePropertyGIFDelayTime] as? Double else { throw ScriptCaptureError.image }
                try require(frame.width == 160 && frame.height == 90, "GIF fixed dimensions")
                try require(delay >= 0.02, "GIF bounded delay")
                elapsed += delay
                let pixel = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
                defer { pixel.deallocate() }
                guard let sample = CGContext(data: pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScriptCaptureError.image }
                sample.draw(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                try require(pixel[3] == 255, "GIF opaque decode")
                try require(index % 2 == 0 ? pixel[0] > 240 && pixel[2] < 10 : pixel[2] > 240 && pixel[0] < 10, "GIF alternating palette colors")
            }
        }
        try require(abs(elapsed - duration) < 0.021, "GIF cumulative real-time quantization")
    }

    @MainActor
    static func decodeVideo(_ url: URL, expectedFrames: Int, expectedDuration: Double) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        FileHandle.standardError.write(Data("VIDEO \(url.lastPathComponent) duration=\(duration) expected=\(expectedDuration) frames=\(expectedFrames)\n".utf8))
        try require(abs(duration - expectedDuration) < 0.002, "MP4 retained terminal duration")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        try require(tracks.count == 1, "MP4 video track")
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(decoded)
        try require(reader.startReading(), "MP4 decoder starts")
        var count = 0
        var last = -Double.infinity
        while let sample = decoded.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            try require(timestamp > last, "MP4 monotonic timestamp")
            if count == 0, let buffer = CMSampleBufferGetImageBuffer(sample) {
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                guard let pixel = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { throw ScriptCaptureError.image }
                try require(pixel[2] > 235 && pixel[0] < 20, "MP4 decoded red color")
            }
            last = timestamp
            count += 1
        }
        try require(reader.status == .completed && count == expectedFrames && count > 0, "MP4 full decode")
    }

    static func firstFragmentBound(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        var offset = 0
        var fragments = 0
        while offset + 8 <= data.count {
            let size = Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            guard size >= 8, size <= data.count - offset else { throw ScriptCaptureError.image }
            if String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii) == "moof" {
                fragments += 1
                if fragments == 2 { return max(1024, offset + 64) }
            }
            offset += size
        }
        throw ScriptCaptureError.image
    }

    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let staged = root.appendingPathComponent("staged")
        let outputs = root.appendingPathComponent("outputs")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: false)
        let scratchBudget = ScriptCaptureBudget(directory: staged, maximumBytes: 64 * 1024 * 1024)
        let outputBudget = ScriptCaptureBudget(directory: outputs, maximumBytes: 16 * 1024 * 1024)
        let red = try image(red: 1, blue: 0)
        let blue = try image(red: 0, blue: 1)
        let redURL = staged.appendingPathComponent("red.png")
        let blueURL = staged.appendingPathComponent("blue.png")
        FileHandle.standardError.write(Data("PHASE PNG\n".utf8))
        try ScriptImageEncoder.png(red, to: redURL, budget: scratchBudget)
        try ScriptImageEncoder.png(blue, to: blueURL, budget: scratchBudget)
        let frames = (0..<400).map { ($0 % 2 == 0 ? redURL : blueURL, Double($0) / 30) }
        let before = residentBytes()
        let gifURL = outputs.appendingPathComponent("full.gif")
        FileHandle.standardError.write(Data("PHASE GIF400\n".utf8))
        let result = try ScriptImageEncoder.gif(frames: frames, fps: 30, endSeconds: 400.0 / 30, to: gifURL, budget: outputBudget)
        let after = residentBytes()
        try require(result.frameCount == 400 && !result.partial, "GIF stress completion")
        try require(before > 0 && after < before + 96 * 1024 * 1024, "GIF memory independent of frame count")
        try decodeGIF(gifURL, count: 400, duration: Double(result.durationMs) / 1000)
        let continuation = ContinuationProbe(3)
        let cancelledURL = outputs.appendingPathComponent("cancelled.gif")
        let cancelled = try ScriptImageEncoder.gif(frames: frames, fps: 30, endSeconds: 400.0 / 30, to: cancelledURL, budget: outputBudget,
                                                    shouldContinue: { continuation.proceed() })
        try require(cancelled.partial && cancelled.frameCount == 3, "GIF cancellation finalizes a complete prefix")
        try decodeGIF(cancelledURL, count: 3, duration: Double(cancelled.durationMs) / 1000)
        let noFrameURL = outputs.appendingPathComponent("cancelled-empty.gif")
        do {
            _ = try ScriptImageEncoder.gif(frames: frames, fps: 30, endSeconds: 400.0 / 30, to: noFrameURL, budget: outputBudget,
                                           shouldContinue: { false })
            throw ScriptCaptureError.image
        } catch ScriptCaptureError.cancelled {
            try require(!FileManager.default.fileExists(atPath: noFrameURL.path), "GIF cancellation before first frame leaves no invalid file")
        }
        let abortedPolicy = ScriptCaptureFinalization(started: 100, alreadyAborted: true)
        let graceFrames = ContinuationProbe(3)
        let abortedURL = outputs.appendingPathComponent("already-aborted.gif")
        let aborted = try ScriptImageEncoder.gif(
            frames: frames, fps: 30, endSeconds: 400.0 / 30, to: abortedURL, budget: outputBudget,
            shouldContinue: { abortedPolicy.allows(now: graceFrames.proceed() ? 101 : 103, isAborted: true) }
        )
        try require(aborted.partial && aborted.frameCount == 3, "Already-aborted caller retains a bounded valid GIF prefix")
        try decodeGIF(abortedURL, count: 3, duration: Double(aborted.durationMs) / 1000)
        let partialManifest = try ScriptArtifactStore.shared.add(
            url: abortedURL, runID: "aborted-fixture", mimeType: "image/gif", owner: "fixture",
            extra: ["partial": true, "width": 160, "height": 90]
        )
        try require(partialManifest["partial"] as? Bool == true, "Aborted caller artifact remains explicitly partial")
        let activePolicy = ScriptCaptureFinalization(started: 100, alreadyAborted: false)
        let newlyAborted = ContinuationProbe(3)
        let newlyAbortedURL = outputs.appendingPathComponent("newly-aborted.gif")
        let newly = try ScriptImageEncoder.gif(
            frames: frames, fps: 30, endSeconds: 400.0 / 30, to: newlyAbortedURL, budget: outputBudget,
            shouldContinue: { activePolicy.allows(now: 101, isAborted: !newlyAborted.proceed()) }
        )
        try require(newly.partial && newly.frameCount == 3, "New abort interrupts normal finalization")
        try decodeGIF(newlyAbortedURL, count: 3, duration: Double(newly.durationMs) / 1000)
        let recoveredURL = outputs.appendingPathComponent("recovered.gif")
        let recovered = try ScriptImageEncoder.gif(frames: Array(frames.prefix(3)), fps: 30, endSeconds: 0.1,
                                                    to: recoveredURL, budget: outputBudget)
        try require(!recovered.partial && recovered.frameCount == 3, "GIF next run succeeds after cancellation")
        try decodeGIF(recoveredURL, count: 3, duration: Double(recovered.durationMs) / 1000)
        let partialDirectory = root.appendingPathComponent("partial")
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: false)
        let partialBudget = ScriptCaptureBudget(directory: partialDirectory, maximumBytes: 2048)
        try Data(repeating: 0, count: 600).write(to: partialDirectory.appendingPathComponent("retained.bin"), options: .withoutOverwriting)
        let partialURL = partialDirectory.appendingPathComponent("partial.gif")
        FileHandle.standardError.write(Data("PHASE PARTIAL\n".utf8))
        let partial = try ScriptImageEncoder.gif(frames: frames, fps: 30, endSeconds: 400.0 / 30, to: partialURL, budget: partialBudget)
        try require(partial.partial && partial.frameCount > 0 && partial.frameCount < 400, "GIF byte-limit valid partial")
        try partialBudget.check()
        try decodeGIF(partialURL, count: partial.frameCount, duration: Double(partial.durationMs) / 1000)
        let rejectedURL = partialDirectory.appendingPathComponent("existing.gif")
        let sentinel = Data("preserved".utf8)
        try sentinel.write(to: rejectedURL, options: .withoutOverwriting)
        do {
            _ = try ScriptImageEncoder.gif(frames: frames, fps: 30, endSeconds: 400.0 / 30, to: rejectedURL, budget: partialBudget)
            throw ScriptCaptureError.image
        } catch { try require(try Data(contentsOf: rejectedURL) == sentinel, "Exclusive existing output preserved") }
        FileHandle.standardError.write(Data("PHASE MP4\n".utf8))
        let closeFailureDirectory = root.appendingPathComponent("close-failure")
        try FileManager.default.createDirectory(at: closeFailureDirectory, withIntermediateDirectories: false)
        let closeFailureBudget = ScriptCaptureBudget(directory: closeFailureDirectory, maximumBytes: 1024) {
            try $0.close()
            throw ScriptCaptureError.image
        }
        let failedOutput = closeFailureDirectory.appendingPathComponent("failed.png")
        do {
            try ScriptImageEncoder.png(red, to: failedOutput, budget: closeFailureBudget)
            throw ScriptCaptureError.duration
        } catch {
            try require(!FileManager.default.fileExists(atPath: failedOutput.path), "Close failure removes only owned output")
        }
        let outputURL = outputs.appendingPathComponent("capture.mp4")
        let writer = try ScriptVideoWriter(url: outputURL, width: 160, height: 90, budget: outputBudget)
        var accepted = 0
        for index in 0..<30 {
            if try writer.append(index % 2 == 0 ? red : blue, seconds: Double(index) / 30) { accepted += 1 }
            try await Task.sleep(nanoseconds: 34_000_000)
        }
        _ = try await writer.finish(endSeconds: 1)
        try require(writer.encodedFrameCount == accepted && !writer.budgetExceeded, "MP4 committed sample count")
        try await decodeVideo(outputURL, expectedFrames: accepted, expectedDuration: 1)
        FileHandle.standardError.write(Data("PHASE MP4_LIMITS\n".utf8))
        let videoLimitDirectory = root.appendingPathComponent("video-limits")
        try FileManager.default.createDirectory(at: videoLimitDirectory, withIntermediateDirectories: false)
        let fragmentLimit = try firstFragmentBound(outputURL)
        let fragmentBudget = ScriptCaptureBudget(directory: videoLimitDirectory, maximumBytes: fragmentLimit)
        let limitedURL = videoLimitDirectory.appendingPathComponent("rejected-fragment.mp4")
        let limited = try ScriptVideoWriter(url: limitedURL, width: 160, height: 90, budget: fragmentBudget)
        for index in 0..<30 {
            _ = try limited.append(index % 2 == 0 ? red : blue, seconds: Double(index) / 30)
            try await Task.sleep(nanoseconds: 34_000_000)
        }
        _ = try await limited.finish(endSeconds: 1)
        try fragmentBudget.check()
        try require(limited.budgetExceeded && limited.encodedFrameCount > 0 && limited.encodedFrameCount < accepted, "Rejected fragment retains only valid prefix")
        try await decodeVideo(limitedURL, expectedFrames: limited.encodedFrameCount, expectedDuration: Double(limited.durationMs) / 1000)
        let tinyDirectory = root.appendingPathComponent("video-tiny")
        try FileManager.default.createDirectory(at: tinyDirectory, withIntermediateDirectories: false)
        let tinyBudget = ScriptCaptureBudget(directory: tinyDirectory, maximumBytes: 1024)
        let tinyURL = tinyDirectory.appendingPathComponent("tiny.mp4")
        let tiny = try ScriptVideoWriter(url: tinyURL, width: 160, height: 90, budget: tinyBudget)
        for index in 0..<12 {
            _ = try tiny.append(red, seconds: Double(index) / 30)
            try await Task.sleep(nanoseconds: 34_000_000)
        }
        do {
            _ = try await tiny.finish(endSeconds: 0.4)
            try require(tiny.encodedFrameCount > 0, "No empty MP4 success")
            try await decodeVideo(tinyURL, expectedFrames: tiny.encodedFrameCount, expectedDuration: Double(tiny.durationMs) / 1000)
        } catch ScriptCaptureError.budget {
            try require(!FileManager.default.fileExists(atPath: tinyURL.path), "Tiny cap has no invalid MP4 artifact")
        }
        try tinyBudget.check()
        let stoppedURL = outputs.appendingPathComponent("stopped.mp4")
        let stopped = try ScriptVideoWriter(url: stoppedURL, width: 160, height: 90, budget: outputBudget)
        try require(try stopped.append(red, seconds: 0), "First stop frame accepted")
        _ = try await stopped.finish(endSeconds: 0.75)
        try await decodeVideo(stoppedURL, expectedFrames: 1, expectedDuration: 0.75)
        let nextURL = outputs.appendingPathComponent("next-run.mp4")
        let next = try ScriptVideoWriter(url: nextURL, width: 160, height: 90, budget: outputBudget)
        try require(try next.append(red, seconds: 0), "Next recording starts without state reset")
        _ = try await next.finish(endSeconds: 0.5)
        try await decodeVideo(nextURL, expectedFrames: 1, expectedDuration: 0.5)
        let burstURL = outputs.appendingPathComponent("backpressure.mp4")
        let burst = try ScriptVideoWriter(url: burstURL, width: 160, height: 90, budget: outputBudget)
        var burstAccepted = 0
        for index in 0..<1000 {
            if try burst.append(red, seconds: Double(index) / 30) { burstAccepted += 1 }
        }
        _ = try await burst.finish(endSeconds: 34)
        try require(burstAccepted > 0 && burstAccepted < 1000 && !burst.budgetExceeded, "Fixed raw-buffer pool enforces backpressure")
        try await decodeVideo(burstURL, expectedFrames: burstAccepted, expectedDuration: 34)
        FileHandle.standardError.write(Data("BACKPRESSURE accepted=\(burstAccepted) dropped=\(1000 - burstAccepted)\n".utf8))
        FileHandle.standardError.write(Data("PHASE HIGH_RESOLUTION\n".utf8))
        let largeRedURL = staged.appendingPathComponent("large-red.png")
        let largeBlueURL = staged.appendingPathComponent("large-blue.png")
        try ScriptImageEncoder.png(image(red: 1, blue: 0, width: 1920, height: 1080), to: largeRedURL, budget: scratchBudget)
        try ScriptImageEncoder.png(image(red: 0, blue: 1, width: 1920, height: 1080), to: largeBlueURL, budget: scratchBudget)
        let largeFrames = (0..<32).map { ($0 % 2 == 0 ? largeRedURL : largeBlueURL, Double($0) / 30) }
        let largeBefore = residentBytes()
        let largeFootprintBefore = footprintBytes()
        let largeURL = outputs.appendingPathComponent("large.gif")
        let largeResult = try ScriptImageEncoder.gif(frames: largeFrames, fps: 30, endSeconds: 32.0 / 30, to: largeURL, budget: outputBudget)
        let largeAfter = residentBytes()
        try require(largeResult.frameCount == 32 && !largeResult.partial, "High-resolution GIF complete")
        let largeFootprintAfter = footprintBytes()
        FileHandle.standardError.write(Data("MEMORY32 rss=\(largeBefore)->\(largeAfter) footprint=\(largeFootprintBefore)->\(largeFootprintAfter)\n".utf8))
        let plateauFrames = (0..<128).map { ($0 % 2 == 0 ? largeRedURL : largeBlueURL, Double($0) / 30) }
        let plateauURL = outputs.appendingPathComponent("plateau.gif")
        let plateau = try ScriptImageEncoder.gif(frames: plateauFrames, fps: 30, endSeconds: 128.0 / 30, to: plateauURL, budget: outputBudget)
        let plateauRSS = residentBytes()
        let plateauFootprint = footprintBytes()
        FileHandle.standardError.write(Data("MEMORY128 rss=\(plateauRSS) footprint=\(plateauFootprint)\n".utf8))
        try require(plateau.frameCount == 128 && !plateau.partial, "High-resolution 128 frames")
        try require(largeFootprintBefore > 0 && plateauFootprint < largeFootprintBefore + 96 * 1024 * 1024, "High-resolution private physical footprint bound")
        try require(plateauFootprint < largeFootprintAfter + 32 * 1024 * 1024, "High-resolution private memory plateau independent of frame count")
        try require(plateauRSS < 384 * 1024 * 1024, "High-resolution resident sanity bound")
        guard let largeSource = CGImageSourceCreateWithURL(largeURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ScriptCaptureError.image }
        for index in 0..<32 {
            try autoreleasepool {
                guard let decoded = CGImageSourceCreateImageAtIndex(largeSource, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ScriptCaptureError.image }
                try require(decoded.width == 1920 && decoded.height == 1080, "High-resolution GIF full decode")
            }
        }
        let overlayPixels = UnsafeMutablePointer<UInt8>.allocate(capacity: 160 * 90 * 4)
        defer { overlayPixels.deallocate() }
        guard let overlay = CGContext(data: overlayPixels, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScriptCaptureError.image }
        overlay.setFillColor(CGColor(gray: 1, alpha: 1))
        overlay.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        ScriptOverlayDrawing.draw(in: overlay, size: CGSize(width: 160, height: 90), viewport: CGSize(width: 160, height: 90),
                                  pointer: nil, marker: ScriptOverlayMarker(point: CGPoint(x: 80, y: 45), started: 0, duration: 1,
                                                                           radius: 20, color: ScriptOverlayDrawing.color("#FF0000"), wobble: true, fade: true),
                                  now: 0.5)
        let center = (45 * 160 + 80) * 4
        overlay.flush()
        FileHandle.standardError.write(Data("OVERLAY rgba=\(overlayPixels[center]),\(overlayPixels[center + 1]),\(overlayPixels[center + 2]),\(overlayPixels[center + 3])\n".utf8))
        try require(overlayPixels[center] > 245 && (120...135).contains(overlayPixels[center + 1]), "Shared overlay fade/color pixel")
        print("High-resolution GIF resident before=\(largeBefore) after=\(largeAfter)")
        let store = ScriptArtifactStore()
        let manifest = try store.add(url: redURL, runID: "run", mimeType: "image/png", owner: "owner", extra: ["width": 160, "height": 90, "partial": true])
        try require(manifest["partial"] as? Bool == true, "Partial provenance preserved")
        let artifact = manifest["id"] as? String ?? ""
        let chunk = store.read(["runId": "run", "artifactId": artifact, "offset": 0, "length": 16], owner: "owner")
        try require(chunk["runId"] as? String == "run" && chunk["artifactId"] as? String == artifact, "Chunk identity")
        try require(store.read(["runId": "run", "artifactId": artifact, "offset": true], owner: "owner")["error"] != nil, "Boolean offset rejected")
        try require(store.read(["runId": "run", "artifactId": artifact], owner: "other")["error"] != nil, "Foreign owner rejected")
        let active = store.read(["runId": "run", "artifactId": artifact], owner: "owner", blockedRunID: "run")
        try require((active["error"] as? [String: Any])?["code"] as? String == "ARTIFACT_NOT_READY" && active["data"] == nil, "Active run bytes withheld")
        let prior = store.read(["runId": "run", "artifactId": artifact], owner: "owner", blockedRunID: "other-current-run")
        try require(prior["data"] != nil, "Prior terminal bytes remain readable")
        let malformed = store.read(["runId": "run", "artifactId": artifact, "offset": true], owner: "owner", blockedRunID: "run")
        try require((malformed["error"] as? [String: Any])?["code"] as? String == "INVALID_PARAM", "Strict validation before active gate")
        print("PASS Apple codec: GIF400 full decode and palette/timing, partial budget, exclusive files, MP4 decode/timestamps, chunks")
        print("GIF resident bytes before=\(before) after=\(after), partialFrames=\(partial.frameCount), videoFrames=\(accepted)")
    }
}
