import AppKit
import CryptoKit
import Network
import WebKit
import XCTest
@testable import KelpieBrowser

final class DownloadPolicyTests: XCTestCase {
    func testAttachmentDispositionAndUnrenderableTypesDownload() {
        XCTAssertTrue(DownloadPolicy.isAttachment("attachment; filename=\"a.zip\""))
        XCTAssertTrue(DownloadPolicy.isAttachment("  Attachment "))
        XCTAssertFalse(DownloadPolicy.isAttachment("inline; filename=\"attachment.pdf\""))
        XCTAssertFalse(DownloadPolicy.isAttachment(nil))
        XCTAssertTrue(DownloadPolicy.shouldDownload(canShowMIMEType: true, contentDisposition: "attachment"))
        XCTAssertTrue(DownloadPolicy.shouldDownload(canShowMIMEType: false, contentDisposition: nil))
        XCTAssertFalse(DownloadPolicy.shouldDownload(canShowMIMEType: true, contentDisposition: "inline"))
    }

    func testFilenamesStayInsideTheDownloadsDirectory() {
        XCTAssertEqual(DownloadPolicy.sanitizedFilename("../../etc/passwd"), "_.._etc_passwd")
        XCTAssertEqual(DownloadPolicy.sanitizedFilename("..hidden"), "hidden")
        XCTAssertEqual(DownloadPolicy.sanitizedFilename(" \n"), "download")
        XCTAssertEqual(DownloadPolicy.sanitizedFilename("Ground037_1K-JPG.zip"), "Ground037_1K-JPG.zip")
    }

    func testTakenNamesGetFinderStyleNumbers() {
        let directory = URL(fileURLWithPath: "/tmp/kelpie-downloads", isDirectory: true)
        let taken: Set<String> = ["a.zip", "a (1).zip", "README"]
        let pick = { (name: String) in
            DownloadPolicy.uniqueDestination(for: name, in: directory) { taken.contains($0.lastPathComponent) }.lastPathComponent
        }
        XCTAssertEqual(pick("a.zip"), "a (2).zip")
        XCTAssertEqual(pick("README"), "README (1)")
        XCTAssertEqual(pick("b.tar"), "b.tar")
    }

    func testOnlyHTTPErrorsRefuseTheBody() {
        XCTAssertNil(DownloadPolicy.refusal(forHTTPStatus: nil))
        XCTAssertNil(DownloadPolicy.refusal(forHTTPStatus: 200))
        XCTAssertEqual(DownloadPolicy.refusal(forHTTPStatus: 403), "HTTP 403")
    }
}

/// Real WebKit downloads against a loopback site whose file needs a session cookie.
@MainActor
final class RealWebKitDownloadTests: XCTestCase {
    private var directory: URL!
    private var store: DownloadStore!
    private var fixture: DownloadSiteFixture!
    private var origin = ""

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelpie-download-tests-\(UUID().uuidString)", isDirectory: true)
        let target = directory!
        store = DownloadStore(directory: { target })
        fixture = try DownloadSiteFixture()
        origin = "http://127.0.0.1:\(try await fixture.start())"
    }

    override func tearDown() async throws {
        fixture?.stop()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testAgentDownloadUsesTheTabSessionAndReportsPathSizeAndHash() async throws {
        let (router, tab) = harness()
        try await load(tab, "\(origin)/login")
        let started = await router.handle(method: "download", body: ["url": "\(origin)/file.zip", "tabId": tab.id.uuidString])
        let id = try XCTUnwrap((started["download"] as? [String: Any])?["id"] as? String)
        XCTAssertEqual((started["download"] as? [String: Any])?["origin"] as? String, "agent")

        let done = try await settled(router, id: id)
        XCTAssertEqual(done["state"] as? String, "complete", "\(done)")
        XCTAssertEqual(done["tabId"] as? String, tab.id.uuidString)
        let path = try XCTUnwrap(done["path"] as? String)
        XCTAssertEqual(URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), DownloadSiteFixture.payload)
        XCTAssertEqual((done["bytesReceived"] as? NSNumber)?.intValue, DownloadSiteFixture.payload.count)
        XCTAssertEqual(done["sha256"] as? String, DownloadSiteFixture.payloadDigest)
    }

    func testSignedOutDownloadFailsWithTheStatusAndLeavesNoFile() async throws {
        let (router, tab) = harness()
        try await load(tab, "\(origin)/page")
        let started = await router.handle(method: "download", body: ["url": "\(origin)/file.zip", "tabId": tab.id.uuidString])
        let id = try XCTUnwrap((started["download"] as? [String: Any])?["id"] as? String)

        let done = try await settled(router, id: id)
        XCTAssertEqual(done["state"] as? String, "failed")
        XCTAssertEqual(done["error"] as? String, "HTTP 403")
        XCTAssertTrue(done["path"] is NSNull)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testPageClickSavesTheAttachmentAndKeepsTheTabOnItsPage() async throws {
        let (router, tab) = harness()
        try await load(tab, "\(origin)/login")
        try await load(tab, "\(origin)/page")
        _ = try await tab.renderer.evaluateJS("document.getElementById('archive').click(); true")

        var record: [String: Any]?
        for _ in 0..<250 where record == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
            let listed = await router.handle(method: "get-downloads", body: [:])
            record = (listed["downloads"] as? [[String: Any]])?.first
        }
        let id = try XCTUnwrap(record?["id"] as? String, "A page click must create a download")
        XCTAssertEqual(record?["origin"] as? String, "page")
        let done = try await settled(router, id: id)
        XCTAssertEqual(done["state"] as? String, "complete", "\(done)")
        XCTAssertEqual(done["sha256"] as? String, DownloadSiteFixture.payloadDigest)
        XCTAssertEqual(tab.renderer.currentURL?.path, "/page", "The source tab keeps its document")
        XCTAssertNil(tab.renderer.lastNavigationError)
        let title = try await tab.renderer.evaluateJS("document.title")
        XCTAssertEqual(title as? String, "Fixture page")
    }

    func testUnknownDownloadIdIsNotFound() async {
        let (router, _) = harness()
        let missing = await router.handle(method: "get-downloads", body: ["id": "absent"])
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? String, "NOT_FOUND")
        let invalid = await router.handle(method: "download", body: ["url": "file:///etc/hosts"])
        XCTAssertEqual((invalid["error"] as? [String: Any])?["code"] as? String, "INVALID_URL")
    }

    // MARK: - Harness

    private func harness() -> (Router, Tab) {
        let context = HandlerContext()
        let router = Router()
        router.handlerContext = context
        let tab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        tab.renderer.downloadStore = store
        context.renderer = tab.renderer
        let windowId = UUID().uuidString
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tab.renderer.makeView()
        WindowRegistry.shared.register(id: windowId, window: window, tabStore: TabStore(isolatedTab: tab))
        addTeardownBlock { @MainActor in
            WindowRegistry.shared.unregister(id: windowId)
            window.orderOut(nil)
            tab.renderer.invalidate()
        }
        DownloadHandler(context: context, downloads: store).register(on: router)
        return (router, tab)
    }

    private func load(_ tab: Tab, _ url: String) async throws {
        tab.renderer.load(url: try XCTUnwrap(URL(string: url)))
        for _ in 0..<250 {
            try await Task.sleep(nanoseconds: 20_000_000)
            if !tab.renderer.isLoading, tab.renderer.currentURL?.absoluteString == url { return }
        }
        XCTFail("Fixture page did not load: \(url)")
    }

    private func settled(_ router: Router, id: String) async throws -> [String: Any] {
        for _ in 0..<500 {
            let listed = await router.handle(method: "get-downloads", body: ["id": id])
            let record = try XCTUnwrap((listed["downloads"] as? [[String: Any]])?.first)
            if record["state"] as? String != "in-progress" { return record }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Download \(id) did not settle")
        return [:]
    }
}

/// `/login` sets a session cookie; `/file.zip` is an attachment only for that session.
private final class DownloadSiteFixture: @unchecked Sendable {
    static let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    static let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

    private let listener: NWListener
    private let queue = DispatchQueue(label: "kelpie.download-fixture")

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    if let port = self.listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: NSError(domain: "KelpieFixture", code: 1))
                    }
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                    guard error == nil, let data else { connection.cancel(); return }
                    let response = Self.respond(to: String(decoding: data, as: UTF8.self))
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private static func respond(to request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let signedIn = lines.contains { $0.lowercased().hasPrefix("cookie:") && $0.contains("session=signed-in") }
        switch path {
        case "/login":
            return reply(200, ["Content-Type: text/html", "Set-Cookie: session=signed-in; Path=/"], Data("<title>Signed in</title>".utf8))
        case "/page":
            let html = "<title>Fixture page</title><a id=\"archive\" href=\"/file.zip\">Archive</a>"
            return reply(200, ["Content-Type: text/html"], Data(html.utf8))
        case "/file.zip" where signedIn:
            return reply(200, ["Content-Type: application/zip", "Content-Disposition: attachment; filename=\"archive.zip\""], payload)
        case "/file.zip":
            return reply(403, ["Content-Type: text/plain"], Data("sign in first".utf8))
        default:
            return reply(404, ["Content-Type: text/plain"], Data("missing".utf8))
        }
    }

    private static func reply(_ status: Int, _ headers: [String], _ body: Data) -> Data {
        let head = (["HTTP/1.1 \(status) Fixture", "Content-Length: \(body.count)", "Connection: close"] + headers)
            .joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        return response
    }
}
