import AppKit

/// One sampler owns movie admission. Raw queues and retained encoded outputs have separate bounds.
@MainActor
final class ScriptCapture {
    private let tab: ScriptWorkflowTab
    private let presentation: ScriptPresentation
    private let options: [String: Any]
    private let formats: Set<String>
    private let directory: URL
    private let rawDirectory: URL
    private let budget: ScriptCaptureBudget
    private let rawBudget: ScriptCaptureBudget
    private let runID: String
    private let fps: Int
    private let maximumDuration: Double
    private var frames: [(URL, Double)] = []
    private var writer: ScriptVideoWriter?
    private var frameTask: Task<Void, Never>?
    private var sampling = false
    private var criticalPending = false
    private var stopped = false
    private var stoppedAt: Double?
    private var started = ProcessInfo.processInfo.systemUptime
    private var nextSlot = 0
    private var initialViewport: ScriptWorkflowTab.Viewport?
    private var outputSize = CGSize.zero
    private var previousDocument: String?
    private var firstDocument: String?
    private var sameDocument = true
    private var droppedFrames = 0
    private var screenshots: [(URL, [String: Any])] = []
    private(set) var failure: String?
    private(set) var manifests: [[String: Any]] = []
    var hasMovies: Bool { formats.contains("gif") || formats.contains("video") }

    init(tab: ScriptWorkflowTab, presentation: ScriptPresentation, options: [String: Any], runID: String) throws {
        self.tab = tab
        self.presentation = presentation
        self.options = options
        self.runID = runID
        formats = Set(options["formats"] as? [String] ?? [])
        fps = options["fps"] as? Int ?? 15
        maximumDuration = Double(options["maxDurationMs"] as? Int ?? 60000) / 1000
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-capture-" + UUID().uuidString)
        rawDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-frames-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do { try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: false) } catch { try? FileManager.default.removeItem(at: directory); throw error }
        budget = ScriptCaptureBudget(directory: directory, maximumBytes: options["maxBytes"] as? Int ?? 67108864)
        rawBudget = ScriptCaptureBudget(directory: rawDirectory, maximumBytes: 67108864)
    }

    func checkTime() throws {
        guard ScriptCaptureDeadline.allows(elapsed: now, maximum: maximumDuration, stopped: stopped) else { throw ScriptWorkflowFailure("CAPTURE_DURATION_LIMIT") }
    }

    func start() async throws {
        started = ProcessInfo.processInfo.systemUptime
        if hasMovies {
            try await sampleMovie(critical: false)
            frameTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled, !stopped, failure == nil {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    if Task.isCancelled || stopped { break }
                    do {
                        if !criticalPending, now >= Double(nextSlot) / Double(fps) { try await sampleMovie(critical: false) }
                    } catch {
                        if !stopped { failure = Self.code(error) }
                    }
                }
            }
        }
    }

    /// Never invent an extra frame outside the FPS schedule or accept a dropped critical sample.
    func ensureMarkerAdmission() async throws {
        guard hasMovies else { return }
        criticalPending = true
        defer { criticalPending = false }
        while sampling { try await tab.check(); try await Task.sleep(nanoseconds: 5_000_000) }
        while now < Double(nextSlot) / Double(fps) {
            try await tab.check()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await sampleMovie(critical: true)
    }

    func screenshot(index: Int) async throws {
        guard formats.contains("screenshots") else { throw ScriptWorkflowFailure("SCREENSHOT_UNSUPPORTED") }
        while sampling { try await tab.check(); try await Task.sleep(nanoseconds: 5_000_000) }
        sampling = true
        defer { sampling = false }
        let (image, viewport, document) = try await frame()
        let url = directory.appendingPathComponent("step-" + String(index) + ".png")
        try ScriptImageEncoder.png(image, to: url, budget: budget)
        screenshots.append((url, ["actionIndex": index, "width": image.width, "height": image.height,
                                  "viewport": viewport.metadata, "documentId": document]))
    }

    /// Stop admitting work immediately; join the existing task after renderer retirement.
    func stopSampling() {
        if stoppedAt == nil { stoppedAt = now }
        stopped = true
        frameTask?.cancel()
    }

    func finish(partial: Bool, discard: Bool = false) async -> [[String: Any]] {
        stopSampling()
        await frameTask?.value
        frameTask = nil
        let end = min(max(stoppedAt ?? now, 1 / Double(fps)), maximumDuration)
        var candidates = screenshots.map { ($0.0, "image/png", $0.1) }
        if let writer {
            do {
                let url = try await writer.finish(endSeconds: end)
                var info = metadata
                info["frameCount"] = writer.encodedFrameCount
                info["durationMs"] = writer.durationMs
                info["droppedFrames"] = droppedFrames + writer.rejectedFrameCount
                info["partial"] = partial || failure != nil || writer.budgetExceeded
                candidates.append((url, "video/mp4", info))
                if writer.budgetExceeded { failure = "CAPTURE_BYTE_LIMIT" }
            } catch { failure = Self.code(error) }
        }
        if formats.contains("gif"), !frames.isEmpty {
            do {
                let frames = frames
                let fps = fps
                let url = directory.appendingPathComponent("capture.gif")
                let budget = budget
                let playback = tab.playback
                let finalization = ScriptCaptureFinalization(
                    started: ProcessInfo.processInfo.systemUptime, alreadyAborted: playback.isAbortRequested()
                )
                let result = try await Task.detached(priority: .utility) {
                    try ScriptImageEncoder.gif(
                        frames: frames,
                        fps: fps,
                        endSeconds: end,
                        to: url,
                        budget: budget,
                        shouldContinue: {
                            finalization.allows(now: ProcessInfo.processInfo.systemUptime, isAborted: playback.isAbortRequested())
                        }
                    )
                }.value
                var info = metadata
                info["frameCount"] = result.frameCount
                info["durationMs"] = result.durationMs
                info["partial"] = partial || failure != nil || result.partial
                candidates.append((url, "image/gif", info))
                if result.partial {
                    if playback.isAbortRequested() {
                        failure = "SCRIPT_ABORTED"
                    } else if ProcessInfo.processInfo.systemUptime >= finalization.deadline {
                        failure = "CAPTURE_FINALIZATION_LIMIT"
                    } else {
                        failure = "CAPTURE_BYTE_LIMIT"
                    }
                }
            } catch { failure = Self.code(error) }
        }
        if discard {
            try? FileManager.default.removeItem(at: rawDirectory)
            try? FileManager.default.removeItem(at: directory)
            return []
        }
        for (url, mime, extra) in candidates {
            do {
                var extra = extra
                extra["partial"] = (extra["partial"] as? Bool ?? false) || partial || failure != nil
                manifests.append(try ScriptArtifactStore.shared.add(
                    url: url, runID: runID, mimeType: mime, owner: tab.grant.owner, extra: extra))
            } catch { failure = "CAPTURE_ARTIFACT_FAILED"; try? FileManager.default.removeItem(at: url) }
        }
        try? FileManager.default.removeItem(at: rawDirectory)
        ScriptCaptureOutputCleanup.prune(directory: directory, retaining: candidates.map { $0.0 })
        if manifests.isEmpty { try? FileManager.default.removeItem(at: directory) }
        return manifests
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime - started }
    private var metadata: [String: Any] {
        var value: [String: Any] = [
            "droppedFrames": droppedFrames, "viewport": initialViewport?.metadata ?? [:],
            "width": Int(outputSize.width), "height": Int(outputSize.height)
        ]
        if sameDocument, let firstDocument { value["documentId"] = firstDocument }
        return value
    }

    private func sampleMovie(critical: Bool) async throws {
        if let failure { throw ScriptWorkflowFailure(failure) }
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        if sampling {
            if critical { throw ScriptWorkflowFailure("CAPTURE_ADMISSION_FAILED") }
            return
        }
        sampling = true
        defer { sampling = false }
        guard now <= maximumDuration else { throw ScriptWorkflowFailure("CAPTURE_DURATION_LIMIT") }
        let slot = max(nextSlot, Int(floor(now * Double(fps))))
        droppedFrames += max(0, slot - nextSlot)
        nextSlot = slot + 1
        let (image, _, _) = try await frame()
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        let timestamp = now
        guard timestamp <= maximumDuration else { throw ScriptWorkflowFailure("CAPTURE_DURATION_LIMIT") }
        var accepted = true
        if formats.contains("video") {
            if writer == nil {
writer = try ScriptVideoWriter(url: directory.appendingPathComponent("capture.mp4"), width: image.width, height: image.height, budget: budget)
            }
            accepted = try writer?.append(image, seconds: timestamp) == true
            if !accepted { droppedFrames += 1 }
            if writer?.budgetExceeded == true { throw ScriptWorkflowFailure("CAPTURE_BYTE_LIMIT") }
        }
        if formats.contains("gif") {
            let url = rawDirectory.appendingPathComponent("frame-" + String(frames.count) + ".png")
            try ScriptImageEncoder.png(image, to: url, budget: rawBudget)
            frames.append((url, timestamp))
        }
        if critical, !accepted { throw ScriptWorkflowFailure("CAPTURE_ADMISSION_FAILED") }
    }

    private func frame() async throws -> (CGImage, ScriptWorkflowTab.Viewport, String) {
        try await tab.check()
        guard now <= maximumDuration else { throw ScriptWorkflowFailure("CAPTURE_DURATION_LIMIT") }
        let viewport = try await tab.viewport()
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        let document = try await tab.documentIdentity()
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        if let initialViewport, !initialViewport.sameGeometry(as: viewport),
           !initialViewport.acceptsScrollbarTransition(to: viewport, documentChanged: previousDocument != document) {
            #if DEBUG
            initialViewport.debugDifference(from: viewport)
            #endif
            throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_CHANGED")
        }
        initialViewport = viewport
        previousDocument = document
        if let firstDocument {
            if firstDocument != document { sameDocument = false }
        } else { firstDocument = document }
        let maximumWidth = options["maxWidth"] as? Int ?? 1280
        let source = try await tab.snapshot(maximumPixels: CGSize(width: maximumWidth, height: 1920), viewport: viewport)
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        guard try await tab.documentIdentity() == document, try await tab.viewport() == viewport else {
            throw ScriptWorkflowFailure("CAPTURE_DOCUMENT_CHANGED")
        }
        guard !stopped else { throw ScriptWorkflowFailure("CAPTURE_STOPPED") }
        var rect = CGRect(origin: .zero, size: source.size)
        guard let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ScriptCaptureError.image }
        let scale = min(Double(maximumWidth) / Double(image.width), 1920 / Double(image.height), 1)
        let width = max(2, Int(Double(image.width) * scale) / 2 * 2)
        let height = max(2, Int(Double(image.height) * scale) / 2 * 2)
        let size = CGSize(width: width, height: height)
        if outputSize != .zero, outputSize != size { throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_CHANGED") }
        outputSize = size
guard let graphics = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { throw ScriptCaptureError.image }
        graphics.draw(image, in: CGRect(origin: .zero, size: size))
        presentation.draw(in: graphics, size: size)
        guard let composed = graphics.makeImage() else { throw ScriptCaptureError.image }
        return (composed, viewport, document)
    }

    private static func code(_ error: Error) -> String {
        if let failure = error as? ScriptWorkflowFailure { return failure.code }
        switch error as? ScriptCaptureError {
        case .budget: return "CAPTURE_BYTE_LIMIT"
        case .duration: return "CAPTURE_DURATION_LIMIT"
        default: return "CAPTURE_FAILED"
        }
    }
}
