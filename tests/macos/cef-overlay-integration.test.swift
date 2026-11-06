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
    var authorized = true
    func check() async throws { if !authorized { throw ScriptWorkflowFailure("AUTHORIZATION_REVOKED") } }
}
@MainActor final class ScriptPresentation {
    struct Frame {
        func draw(in graphics: CGContext, size: CGSize) {
            graphics.setFillColor(CGColor(gray: 0, alpha: 1))
            graphics.fill(CGRect(x: 5, y: 5, width: 5, height: 5))
        }
    }
    func frame() -> Frame { Frame() }
}
@MainActor enum ScriptRendererDeadline {
    static func run<T>(renderer: any RendererEngine, seconds: UInt64 = 5, lease: Lease,
                       cancelled: @escaping @MainActor () -> Bool, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        try await operation()
    }
}
@main struct Main {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-overlay-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("KELPIE_CEF_OVERLAY_DIRECTORY", directory.path, 1)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let tab = ScriptWorkflowTab(), scene = ScriptPresentation(), runID = UUID().uuidString
        let capture = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: runID, isCurrent: { true })
        for _ in 0..<5 {
            capture.receive(data, receipt: ProcessInfo.processInfo.systemUptime, context: capture.context()!)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard await capture.prepare(), await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() }, inspect: { true }, current: { true }, move: { capture.publish() }
        ) else { fatalError("valid output missing") }
        let output = directory.appendingPathComponent("overlay-" + runID + ".mp4")
        guard FileManager.default.fileExists(atPath: output.path) else { fatalError("not published") }
        capture.discard()
        guard FileManager.default.fileExists(atPath: output.path) else { fatalError("published output removed") }
        let rejectedID = UUID().uuidString
        let rejected = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: rejectedID, isCurrent: { true })
        rejected.receive(data, receipt: ProcessInfo.processInfo.systemUptime, context: rejected.context()!)
        try await Task.sleep(nanoseconds: 100_000_000)
        tab.authorized = false
        guard !(await rejected.prepare()) else { fatalError("revocation accepted") }
        rejected.discard()
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("overlay-" + rejectedID + ".mp4").path) else {
            fatalError("revoked output escaped")
        }
        tab.authorized = true
        let lateID = UUID().uuidString
        let late = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: lateID, isCurrent: { true })
        for _ in 0..<3 {
            late.receive(data, receipt: ProcessInfo.processInfo.systemUptime, context: late.context()!)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard await late.prepare() else { fatalError("late fixture not prepared") }
        tab.authorized = false
        let lateAllowed = await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() }, inspect: { true }, current: { true }, move: { late.publish() }
        )
        guard !lateAllowed else { fatalError("late revocation accepted") }
        late.discard()
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("overlay-" + lateID + ".mp4").path) else {
            fatalError("late revoked output escaped")
        }
        tab.authorized = true
        let viewportID = UUID().uuidString
        let viewportCapture = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: viewportID, isCurrent: { true })
        for _ in 0..<3 {
            viewportCapture.receive(data, receipt: ProcessInfo.processInfo.systemUptime, context: viewportCapture.context()!)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard await viewportCapture.prepare() else { fatalError("viewport fixture not prepared") }
        var moved = false
        let viewportAllowed = await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() }, inspect: { false }, current: { true },
            move: { moved = true; return viewportCapture.publish() }
        )
        viewportCapture.discard()
        guard !viewportAllowed, !moved,
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("overlay-" + viewportID + ".mp4").path) else {
            fatalError("changed viewport accepted")
        }
        let lateAuthorityAllowed = await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() },
            inspect: { tab.authorized = false; try await tab.check(); return true },
            current: { true }, move: { moved = true; return true }
        )
        guard !lateAuthorityAllowed, !moved else { fatalError("late authority change accepted") }
        tab.authorized = true
        unsetenv("KELPIE_CEF_STATIC_TEST")
        let ordinaryID = UUID().uuidString
        let ordinary = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: ordinaryID, isCurrent: { true })
        guard !(await ordinary.prepare()) else { fatalError("ordinary empty stream accepted") }
        ordinary.discard()
        setenv("KELPIE_CEF_STATIC_TEST", "1", 1)
        let sparseID = UUID().uuidString
        let sparse = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: sparseID, isCurrent: { true })
        sparse.receive(data, receipt: ProcessInfo.processInfo.systemUptime, context: sparse.context()!)
        try await Task.sleep(nanoseconds: 100_000_000)
        guard await sparse.prepare() else { fatalError("single frame not classified sparse") }
        let sparseAllowed = await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() }, inspect: { true }, current: { true }, move: { sparse.publish() }
        )
        sparse.discard()
        guard sparseAllowed,
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("overlay-" + sparseID + ".mp4").path) else {
            fatalError("sparse observation published placeholder")
        }
        let deniedID = UUID().uuidString
        let denied = try ScriptHostedOverlayCapture(tab: tab, presentation: scene, runID: deniedID, isCurrent: { true })
        guard await denied.prepare() else { fatalError("empty stream not classified sparse") }
        tab.authorized = false
        let deniedAllowed = await ScriptHostedOverlayAudit.publish(
            check: { try await tab.check() }, inspect: { true }, current: { true }, move: { denied.publish() }
        )
        denied.discard()
        guard !deniedAllowed,
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("overlay-" + deniedID + ".mp4").path) else {
            fatalError("sparse revocation accepted")
        }
        unsetenv("KELPIE_CEF_STATIC_TEST")
        print("PASS: real writer, late refusals and zero/one-frame sparse disposal")
    }
}
