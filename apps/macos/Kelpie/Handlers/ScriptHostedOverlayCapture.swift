#if DEBUG && KELPIE_HOSTED_STREAM_TEST
import AppKit

/// Private synthetic-fixture output; never publishes before the final authority audit.
@MainActor
final class ScriptHostedOverlayCapture {
    final class Context: NSObject {
        let frame: ScriptPresentation.Frame
        init(_ frame: ScriptPresentation.Frame) { self.frame = frame }
    }

    private let tab: ScriptWorkflowTab
    private let presentation: ScriptPresentation
    private let isCurrent: () -> Bool
    private let directory: URL
    private let output: URL
    private let started = ProcessInfo.processInfo.systemUptime
    private var writer: ScriptVideoWriter?
    private var prepared: URL?
    private var outputSize = CGSize.zero
    private var pending: Task<Void, Never>?
    private var failed = false
    private var closed = false
    private var dropped = 0
    private var accepted = 0

    init(tab: ScriptWorkflowTab, presentation: ScriptPresentation, runID: String, isCurrent: @escaping () -> Bool) throws {
        guard UUID(uuidString: runID) != nil,
              let path = ProcessInfo.processInfo.environment["KELPIE_CEF_OVERLAY_DIRECTORY"],
              path.hasPrefix("/"), !path.contains("\0") else { throw ScriptWorkflowFailure("INVALID_PARAM") }
        self.tab = tab
        self.presentation = presentation
        self.isCurrent = isCurrent
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-overlay-" + UUID().uuidString)
        output = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("overlay-" + runID + ".mp4")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw ScriptWorkflowFailure("CAPTURE_FAILED") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func context() -> Context? { !closed && isCurrent() ? Context(presentation.frame()) : nil }

    func receive(_ data: Data, receipt: Double, context: Context) {
        guard !failed, !closed else { return }
        guard pending == nil else { dropped += 1; return }
        pending = Task { @MainActor [self] in
            defer { pending = nil }
            do {
                try await tab.check()
                guard !closed, !Task.isCancelled, isCurrent(), receipt >= started, let source = NSImage(data: data) else {
                    throw ScriptWorkflowFailure("CAPTURE_DOCUMENT_CHANGED")
                }
                let image = try ScriptCaptureCompositor.compose(source, maximumWidth: 640, outputSize: &outputSize) { graphics, size in
                    context.frame.draw(in: graphics, size: size)
                }
                if writer == nil {
                    let budget = ScriptCaptureBudget(directory: directory, maximumBytes: 32 * 1024 * 1024)
                    writer = try ScriptVideoWriter(
                        url: directory.appendingPathComponent("overlay.mp4"),
                        width: image.width,
                        height: image.height,
                        budget: budget
                    )
                }
                if try writer?.append(image, seconds: receipt - started) == true { accepted += 1 } else { dropped += 1 }
            } catch { failed = true }
        }
    }

    func prepare() async -> Bool {
        closed = true
        do {
            if let pending {
                try await ScriptRendererDeadline.run(
                    renderer: tab.renderer,
                    seconds: 2,
                    lease: tab.router.browserLease,
                    cancelled: { self.tab.isAborted },
                    operation: { await pending.value }
                )
            }
            try await tab.check()
            guard !failed, isCurrent(), let writer, !writer.budgetExceeded, accepted > 1 else { return false }
            let end = max(ProcessInfo.processInfo.systemUptime - started, 1.0 / 30.0)
            let temporary = try await writer.finish(endSeconds: end)
            try await tab.check()
            guard !writer.budgetExceeded, isCurrent() else { return false }
            prepared = temporary
            self.writer = nil
            return true
        } catch { return false }
    }

    func publish() async -> Bool {
        do {
            try await tab.check()
            guard let prepared, isCurrent(), !FileManager.default.fileExists(atPath: output.path) else { return false }
            // No suspension between the final authority/identity check and publication.
            try FileManager.default.moveItem(at: prepared, to: output)
            self.prepared = nil
            print("[WorkflowHostedOverlay] event=complete accepted=\(accepted) dropped=\(dropped)")
            return true
        } catch { return false }
    }

    func discard() {
        closed = true
        pending?.cancel()
        writer?.discard()
        writer = nil
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
