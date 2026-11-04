import AVFoundation
import Foundation

/// Only complete init/fragment units reach the exclusive file. Rejected fragments leave a playable prefix.
final class ScriptVideoSegmentSink: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let output: ScriptCaptureBudget.Output
    private let url: URL
    private var initialized = false
    private var invalid = false
    private var exhausted = false
    private var frames = 0
    private var rejected = 0
    private var end = 0.0
    private var closed = false

    init(url: URL, budget: ScriptCaptureBudget) throws {
        self.url = url
        output = try budget.output(url: url)
    }

    deinit {
        if !closed {
            try? output.close()
            try? FileManager.default.removeItem(at: url)
        }
    }

    var budgetExceeded: Bool { lock.withLock { exhausted } }
    var frameCount: Int { lock.withLock { frames } }
    var rejectedFrames: Int { lock.withLock { rejected } }
    var durationMs: Int { lock.withLock { Int(end * 1000) } }

    func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData data: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        let count = segmentType == .separable ? Self.samples(data, lower: 0, upper: data.count, depth: 0) : 0
        guard !invalid else { return }
        if exhausted { rejected += max(count, 0); return }
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { exhausted = true; rejected += max(count, 0); return }
        if segmentType == .initialization {
            guard !initialized, frames == 0 else { invalid = true; return }
        } else {
            guard segmentType == .separable, initialized, count > 0,
                  let report = segmentReport?.trackReports.first(where: { $0.mediaType == .video }),
                  report.earliestPresentationTimeStamp.seconds.isFinite, report.duration.seconds.isFinite, report.duration.seconds > 0 else {
                invalid = true
                return
            }
        }
        do {
            try output.appendUnit(data)
            if segmentType == .initialization { initialized = true } else {
                frames += count
                if let report = segmentReport?.trackReports.first(where: { $0.mediaType == .video }) {
                    end = max(end, report.earliestPresentationTimeStamp.seconds + report.duration.seconds)
                }
            }
        } catch ScriptCaptureError.budget {
            exhausted = true
            rejected += max(count, 0)
        } catch { invalid = true }
    }

    func finish() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        do {
            try output.close()
            closed = true
            guard !invalid, initialized, frames > 0 else {
                throw exhausted ? ScriptCaptureError.budget : ScriptCaptureError.image
            }
            return url
        } catch {
            closed = true
            try? output.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        try? output.close()
        try? FileManager.default.removeItem(at: url)
    }

    /// ISO BMFF trun sample counts; bounded parsing only of the framework-produced complete fragment.
    private static func samples(_ data: Data, lower: Int, upper: Int, depth: Int) -> Int {
        guard depth <= 4 else { return -1 }
        var cursor = lower
        var total = 0
        while cursor < upper {
            guard upper - cursor >= 8 else { return -1 }
            let shortSize = word(data, cursor)
            var header = 8
            var size = Int(shortSize)
            if shortSize == 1 {
                guard upper - cursor >= 16, word(data, cursor + 8) == 0 else { return -1 }
                header = 16
                size = Int(word(data, cursor + 12))
            } else if shortSize == 0 { size = upper - cursor }
            guard size >= header, size <= upper - cursor else { return -1 }
            let type = String(bytes: data[(cursor + 4)..<(cursor + 8)], encoding: .ascii) ?? ""
            if type == "moof" || type == "traf" {
                let nested = samples(data, lower: cursor + header, upper: cursor + size, depth: depth + 1)
                guard nested >= 0 else { return -1 }
                total += nested
            } else if type == "trun" {
                guard size >= header + 8 else { return -1 }
                total += Int(word(data, cursor + header + 4))
            }
            guard total <= 1000 else { return -1 }
            cursor += size
        }
        return total
    }

    private static func word(_ data: Data, _ at: Int) -> UInt32 {
        UInt32(data[at]) << 24 | UInt32(data[at + 1]) << 16 | UInt32(data[at + 2]) << 8 | UInt32(data[at + 3])
    }
}
