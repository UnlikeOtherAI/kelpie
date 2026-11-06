import AppKit
@MainActor protocol RendererEngine: AnyObject {}
@MainActor final class Renderer: RendererEngine {}
final class Lease {}
@MainActor final class Router { let browserLease = Lease() }
struct ScriptWorkflowFailure: Error { init(_ code: String) {} }
@MainActor final class ScriptWorkflowTab {
    let renderer: any RendererEngine = Renderer()
    let router = Router()
    var isAborted = false
    var continuation: CheckedContinuation<Void, Never>?
    func check() async throws { await withCheckedContinuation { continuation = $0 } }
}
@MainActor final class ScriptPresentation {
    struct Frame { func draw(in: CGContext, size: CGSize) {} }
    func frame() -> Frame { Frame() }
}
@MainActor enum ScriptCaptureCompositor {
    static var called = false
    static func compose(_ source: NSImage, maximumWidth: Int, outputSize: inout CGSize, draw: (CGContext, CGSize) -> Void) throws -> CGImage { called = true; fatalError() }
}
final class ScriptCaptureBudget { init(directory: URL, maximumBytes: Int) {} }
@MainActor final class ScriptVideoWriter {
    var budgetExceeded: Bool { false }
    init(url: URL, width: Int, height: Int, budget: ScriptCaptureBudget) throws { fatalError() }
    func append(_ image: CGImage, seconds: Double) throws -> Bool { fatalError() }
    func finish(endSeconds: Double? = nil) async throws -> URL { fatalError() }
    func discard() {}
}
@MainActor enum ScriptRendererDeadline {
    static func run<T>(renderer: any RendererEngine, seconds: UInt64 = 5, lease: Lease,
                       cancelled: @escaping @MainActor () -> Bool, operation: @escaping @MainActor () async throws -> T) async throws -> T { try await operation() }
}
@main struct Main {
    @MainActor static func main() async throws {
        setenv("KELPIE_CEF_OVERLAY_DIRECTORY", NSTemporaryDirectory(), 1)
        let tab = ScriptWorkflowTab(), presentation = ScriptPresentation()
        let capture = try ScriptHostedOverlayCapture(tab: tab, presentation: presentation, runID: UUID().uuidString, isCurrent: { true })
        let context = capture.context()!
        capture.receive(Data([0]), receipt: ProcessInfo.processInfo.systemUptime, context: context)
        while tab.continuation == nil { await Task.yield() }
        capture.discard()
        tab.continuation?.resume()
        for _ in 0..<10 { await Task.yield() }
        assert(!ScriptCaptureCompositor.called)
        assert(capture.context() == nil)
        print("PASS: closed gate prevents delayed authority callback from writing")
    }
}
