import CoreGraphics
import Darwin
import Foundation

/// Encoders operate on private run files. The final response contains only owner-bound store entries.
@MainActor
final class IOSWorkflowMedia {
    typealias Body = [String: Any]
    private static var processRoot: URL?
    private let runID: String
    private let owner: String
    private let formats: Set<String>
    private let fps: Int
    private let output: ScriptCaptureBudget
    private let scratch: ScriptCaptureBudget
    private var frames: [(URL, Double)] = []
    private var steps: [(URL, Body)] = []
    private var first: Body = [:]
    private var video: ScriptVideoWriter?
    private var videoDrops = 0
    private var firstTime: Double?
    private(set) var failure: IOSWorkflowFailure?
    #if DEBUG
    private var geometryEvidence = IOSG08GeometryEvidence()
    #endif

    init(runID: String, owner: String, settings: Body) throws {
        self.runID = runID
        self.owner = owner
        formats = Set(settings["formats"] as? [String] ?? [])
        fps = settings["fps"] as? Int ?? 15
        let limit = settings["maxBytes"] as? Int ?? 67108864
        let root = try Self.captureDirectory()
        output = ScriptCaptureBudget(directory: root.appendingPathComponent("workflow-" + runID), maximumBytes: limit)
        scratch = ScriptCaptureBudget(directory: root.appendingPathComponent("frames-" + runID), maximumBytes: limit)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try FileManager.default.createDirectory(at: output.directory, withIntermediateDirectories: false, attributes: attributes)
        do {
            try FileManager.default.createDirectory(at: scratch.directory, withIntermediateDirectories: false, attributes: attributes)
        } catch {
            try? FileManager.default.removeItem(at: output.directory)
            throw error
        }
    }

    private static func captureDirectory() throws -> URL {
        if let processRoot {
            let children = try FileManager.default.contentsOfDirectory(at: processRoot, includingPropertiesForKeys: nil)
            // The store expires files individually. rmdir removes only an empty run directory.
            for child in children { _ = Darwin.rmdir(child.path) }
            return processRoot
        }
        // No grant or artifact ID survives a listener/process restart. The app owns this exact private namespace.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-workflow-capture-v1", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.complete])
        processRoot = directory
        return directory
    }

    func receive(_ image: CGImage, seconds: Double, step: Int?, document: String, viewport: IOSWorkflowTab.Viewport) throws -> Bool {
        #if DEBUG
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            if (0...10000).contains(elapsedMs) { print("[WorkflowCaptureEncode] elapsedMs=" + String(elapsedMs)) }
        }
        #endif
        #if DEBUG
        geometryEvidence.record(document: document, viewport: viewport)
        #endif
        let stamp: Body = ["width": image.width, "height": image.height, "documentId": document, "viewport": viewport.metadata]
        if first.isEmpty { first = stamp; firstTime = seconds }
        let time = max(0, seconds - (firstTime ?? seconds))
        do {
            if let step {
                let url = output.directory.appendingPathComponent("step-\(step).png")
                try ScriptImageEncoder.png(image, to: url, budget: output)
                steps.append((url, stamp.merging(["actionIndex": step]) { _, new in new }))
            }
            if formats.contains("gif") {
                let url = scratch.directory.appendingPathComponent("frame-\(frames.count).png")
                try ScriptImageEncoder.png(image, to: url, budget: scratch)
                frames.append((url, time))
            }
            var admitted = true
            if formats.contains("video") {
                try output.check()
                if video == nil {
                    video = try ScriptVideoWriter(
                        url: output.directory.appendingPathComponent("movie.mp4"),
                        width: image.width,
                        height: image.height,
                        budget: output
                    )
                }
                admitted = try video?.append(image, seconds: time) == true
                if !admitted { videoDrops += 1 }
                if video?.budgetExceeded == true { throw IOSWorkflowFailure("CAPTURE_BUDGET_EXCEEDED") }
                try output.check()
            }
            return admitted
        } catch let failure as IOSWorkflowFailure { throw failure } catch ScriptCaptureError.budget {
            throw IOSWorkflowFailure("CAPTURE_BUDGET_EXCEEDED")
        } catch { throw IOSWorkflowFailure("CAPTURE_FAILED") }
    }

    func finish(elapsed: Double, dropped: Int, partial: Bool, discard: Bool, isAborted: @escaping @Sendable () -> Bool) async -> [Body] {
        let alreadyAborted = isAborted()
        let deadline = ProcessInfo.processInfo.systemUptime + (alreadyAborted ? 2 : 40)
        let shouldContinue: @Sendable () -> Bool = {
            ProcessInfo.processInfo.systemUptime < deadline && (alreadyAborted || !isAborted())
        }
        var pending = steps.map { ($0.0, "image/png", $0.1) }
        let end = max(0.001, elapsed - (firstTime ?? 0))
        var retained: Set<URL> = []
        defer {
            for directory in [output.directory, scratch.directory] {
                IOSCaptureCleanup.prune(directory: directory, retaining: retained)
            }
        }
        output.reserveFooter(0)
        if let video {
            do {
                let url = try await video.finish(endSeconds: end)
                do { try output.check() } catch { try? FileManager.default.removeItem(at: url); throw error }
                var extra = first
                extra["frameCount"] = video.encodedFrameCount
                extra["durationMs"] = video.durationMs
                extra["droppedFrames"] = videoDrops + video.rejectedFrameCount + dropped
                #if DEBUG
                extra["geometry"] = geometryEvidence.manifest(encodedFrames: video.encodedFrameCount)
                #endif
                if video.budgetExceeded { failure = IOSWorkflowFailure("CAPTURE_BUDGET_EXCEEDED") }
                pending.append((url, "video/mp4", extra))
            } catch {
                try? FileManager.default.removeItem(at: output.directory.appendingPathComponent("movie.mp4"))
                failure = IOSWorkflowFailure("VIDEO_FINALIZATION_FAILED")
            }
        }
        if !discard, formats.contains("gif"), !frames.isEmpty {
            let url = output.directory.appendingPathComponent("animation.gif")
            let frames = frames, fps = fps, budget = output
            do {
                let result = try await Task.detached(priority: .utility) {
                    try ScriptImageEncoder.gif(frames: frames, fps: fps, endSeconds: end, to: url, budget: budget, shouldContinue: shouldContinue)
                }.value
                var extra = first
                extra["durationMs"] = result.durationMs
                extra["frameCount"] = result.frameCount
                extra["droppedFrames"] = dropped
                #if DEBUG
                extra["geometry"] = geometryEvidence.manifest(encodedFrames: result.frameCount)
                #endif
                if result.partial {
                    let limit = shouldContinue() ? "CAPTURE_BUDGET_EXCEEDED" : "CAPTURE_FINALIZATION_LIMIT"
                    failure = IOSWorkflowFailure(isAborted() ? "SCRIPT_ABORTED" : limit)
                }
                pending.append((url, "image/gif", extra))
            } catch { failure = IOSWorkflowFailure(isAborted() ? "SCRIPT_ABORTED" : "GIF_FINALIZATION_FAILED") }
        }
        guard !discard else { return [] }
        var manifests: [Body] = []
        for (url, type, var extra) in pending {
            do {
                extra["partial"] = partial || failure != nil || isAborted()
                let entry = try ScriptArtifactStore.shared.add(url: url, runID: runID, mimeType: type, owner: owner, extra: extra)
                retained.insert(url)
                manifests.append(entry)
            } catch { failure = IOSWorkflowFailure("ARTIFACT_REGISTRATION_FAILED") }
        }
        if failure != nil || isAborted() {
            for index in manifests.indices { manifests[index]["partial"] = true }
        }
        return manifests
    }
}
