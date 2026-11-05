import AVFoundation
import CoreGraphics
import CoreVideo
import UniformTypeIdentifiers

/// Native H.264 with explicit sample durations and bounded, complete fragmented-MP4 output.
@MainActor
final class ScriptVideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let pool: CVPixelBufferPool
    private let width: Int
    private let height: Int
    private let sink: ScriptVideoSegmentSink
    private var pending: (CVPixelBuffer, Double)?
    private var format: CMVideoFormatDescription?
    private var lastAcceptedSeconds = -Double.infinity
    private var submittedFrames = 0

    var budgetExceeded: Bool { sink.budgetExceeded }
    var encodedFrameCount: Int { sink.frameCount }
    var rejectedFrameCount: Int { sink.rejectedFrames }
    var durationMs: Int { sink.durationMs }

    init(url: URL, width: Int, height: Int, budget: ScriptCaptureBudget) throws {
        guard (2...1920).contains(width), (2...1920).contains(height) else { throw ScriptCaptureError.image }
        self.width = width
        self.height = height
        sink = try ScriptVideoSegmentSink(url: url, budget: budget)
        writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 0.25, preferredTimescale: 600)
        writer.initialSegmentStartTime = .zero
        writer.delegate = sink
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalDurationKey: 0.25
            ]
        ])
        input.expectsMediaDataInRealTime = true
        var createdPool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &createdPool) == kCVReturnSuccess,
              let createdPool else { throw ScriptCaptureError.image }
        pool = createdPool
        guard writer.canAdd(input) else { throw ScriptCaptureError.image }
        writer.add(input)
        guard writer.startWriting() else { throw ScriptCaptureError.image }
        writer.startSession(atSourceTime: .zero)
    }

    /// One pending frame supplies the duration until the next accepted timestamp.
    /// A pool of at most three raw buffers bounds encoder backpressure independently of FPS.
    func append(_ image: CGImage, seconds: Double) throws -> Bool {
        guard !sink.budgetExceeded else { return false }
        guard seconds.isFinite, seconds >= 0, seconds <= 300, seconds > lastAcceptedSeconds else { throw ScriptCaptureError.duration }
        guard image.width == width, image.height == height, writer.status == .writing else { throw ScriptCaptureError.image }
        if pending != nil, !input.isReadyForMoreMediaData { return false }
        var allocated: CVPixelBuffer?
        let limit = [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, limit, &allocated)
        if status == kCVReturnWouldExceedAllocationThreshold { return false }
        guard status == kCVReturnSuccess, let buffer = allocated else { throw ScriptCaptureError.image }
        try paint(image, into: buffer)
        if let pending { try submit(pending, endingAt: seconds) }
        pending = (buffer, seconds)
        lastAcceptedSeconds = seconds
        return true
    }

    func finish(endSeconds: Double? = nil) async throws -> URL {
        let end = endSeconds ?? lastAcceptedSeconds + 1 / 30
        guard end.isFinite, end <= 300, end > lastAcceptedSeconds, pending != nil || submittedFrames > 0 else {
            writer.cancelWriting()
            sink.discard()
            throw ScriptCaptureError.duration
        }
        do {
            if let pending, !sink.budgetExceeded {
                let deadline = ProcessInfo.processInfo.systemUptime + 2
                while !input.isReadyForMoreMediaData, writer.status == .writing, !sink.budgetExceeded,
                      ProcessInfo.processInfo.systemUptime < deadline {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                if !sink.budgetExceeded {
                    guard input.isReadyForMoreMediaData else { throw ScriptCaptureError.image }
                    try submit(pending, endingAt: end)
                }
            }
            pending = nil
            writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw ScriptCaptureError.image }
            guard sink.budgetExceeded || sink.frameCount == submittedFrames else { throw ScriptCaptureError.image }
            return try sink.finish()
        } catch {
            pending = nil
            writer.cancelWriting()
            sink.discard()
            throw error
        }
    }

    private func paint(_ image: CGImage, into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, space, .shouldPropagate)
        guard let graphics = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { throw ScriptCaptureError.image }
        graphics.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        if format == nil {
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescriptionOut: &format
            ) == noErr else { throw ScriptCaptureError.image }
        }
    }

    private func submit(_ frame: (CVPixelBuffer, Double), endingAt end: Double) throws {
        guard let format, end > frame.1 else { throw ScriptCaptureError.duration }
        let timestamp = CMTime(value: Int64((frame.1 * 600).rounded()), timescale: 600)
        let terminal = CMTime(value: Int64((end * 600).rounded()), timescale: 600)
        let duration = CMTimeSubtract(terminal, timestamp)
        guard duration > .zero else { throw ScriptCaptureError.duration }
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.0,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr,
              let sample, input.append(sample) else { throw ScriptCaptureError.image }
        submittedFrames += 1
    }
}
