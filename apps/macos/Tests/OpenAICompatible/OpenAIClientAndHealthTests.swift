import XCTest
@testable import Kelpie

final class OpenAIClientAndHealthTests: XCTestCase {
    private func client(_ transport: FakeOpenAITransport, key: String? = nil) throws -> OpenAIEndpointClient {
        OpenAIEndpointClient(baseURL: try .normalize("http://127.0.0.1:18880/v1"), apiKey: key, transport: transport)
    }

    private func discoveryError(status: Int, body: String = "", headers: [String: String] = [:]) async throws -> OpenAIEndpointError? {
        let transport = FakeOpenAITransport { _ in .init(status: status, headers: headers, body: Data(body.utf8)) }
        do {
            _ = try await client(transport).listModels()
            return nil
        } catch {
            return error as? OpenAIEndpointError
        }
    }

    // MARK: - Authentication

    func testNoAuthorizationHeaderWithoutKey() async throws {
        let transport = FakeOpenAITransport { _ in .init(body: OpenAIFixtures.json(OpenAIFixtures.strataModels)) }
        _ = try await client(transport).listModels()
        _ = try await client(transport, key: "").listModels()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "http://127.0.0.1:18880/v1/models")
    }

    func testBearerHeaderWhenKeyIsSet() async throws {
        let transport = FakeOpenAITransport { _ in .init(body: OpenAIFixtures.json(OpenAIFixtures.strataModels)) }
        _ = try await client(transport, key: "sk-test-123").listModels()
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-123")
    }

    func testServerErrorTextIsTruncatedAndRedacted() async throws {
        let leak = "{\"error\":{\"message\":\"bad key sk-test-123 \(String(repeating: "x", count: 500))\"}}"
        let transport = FakeOpenAITransport { _ in .init(status: 500, body: Data(leak.utf8)) }
        do {
            _ = try await client(transport, key: "sk-test-123").chat(body: [:], stream: false)
            XCTFail("expected error")
        } catch let error as OpenAIEndpointError {
            XCTAssertFalse(error.message.contains("sk-test-123"))
            XCTAssertTrue(error.message.contains("[redacted]"))
            XCTAssertLessThan(error.message.count, 400)
        }
    }

    // MARK: - Discovery outcomes

    func testDiscoveryStatusMapping() async throws {
        let auth = try await discoveryError(status: 401)
        XCTAssertEqual(auth, .authFailed)
        let forbidden = try await discoveryError(status: 403)
        XCTAssertEqual(forbidden, .authFailed)
        let unsupported = try await discoveryError(status: 404)
        XCTAssertEqual(unsupported, .discoveryUnsupported)
        let loading = try await discoveryError(status: 503, body: "{\"error\":{\"message\":\"Loading model\"}}")
        XCTAssertEqual(loading, .loading("Loading model"))
        let redirect = try await discoveryError(status: 302, headers: ["Location": "http://evil.example:80/v1/models"])
        XCTAssertEqual(redirect, .redirectRefused("http://evil.example:80"))
        let html = try await discoveryError(status: 200, body: "<html>proxy login</html>")
        XCTAssertEqual(html?.code, "ENDPOINT_MALFORMED_RESPONSE")
        let wrongShape = try await discoveryError(status: 200, body: "{\"object\":\"list\"}")
        XCTAssertEqual(wrongShape?.code, "ENDPOINT_MALFORMED_RESPONSE")
    }

    func testUnreachableTransportError() async throws {
        let transport = FakeOpenAITransport { _ in .init(error: OpenAIEndpointError.unreachable("connection refused")) }
        do {
            _ = try await client(transport).listModels()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? OpenAIEndpointError)?.code, "ENDPOINT_UNREACHABLE")
        }
    }

    func testModelListParsingAcrossServers() throws {
        let strata = try OpenAIModelListParser.parse(OpenAIFixtures.json(OpenAIFixtures.strataModels))
        XCTAssertEqual(strata, [OpenAIModelInfo(id: "qwen3.8-flash-next-ud-q4_k_xl", contextWindow: 131_072, vision: false, status: .loaded)])

        let vllm = try OpenAIModelListParser.parse(OpenAIFixtures.json(["data": [["id": "Qwen/Qwen3-8B", "max_model_len": 32_768]]]))
        XCTAssertEqual(vllm.first?.contextWindow, 32_768)
        XCTAssertNil(vllm.first?.vision, "no modality metadata means unknown, not text-only")

        let lmStudio = try OpenAIModelListParser.parse(OpenAIFixtures.json([
            "data": [["id": "gemma", "state": "not-loaded", "max_context_length": 8_192, "capabilities": ["vision"]]]
        ]))
        XCTAssertEqual(lmStudio.first, OpenAIModelInfo(id: "gemma", contextWindow: 8_192, vision: true, status: .unloaded))

        let mixed = try OpenAIModelListParser.parse(OpenAIFixtures.json(["data": [["object": "model"], ["id": ""], ["id": "ok"], "junk"]]))
        XCTAssertEqual(mixed.map(\.id), ["ok"])
        XCTAssertEqual(try OpenAIModelListParser.parse(OpenAIFixtures.json(["data": []])), [])
    }

    // MARK: - Health transitions

    private let model = "qwen3.8-flash-next-ud-q4_k_xl"
    private var listed: [OpenAIModelInfo] { [OpenAIModelInfo(id: model, contextWindow: 131_072, vision: false, status: .loaded)] }

    private func evaluate(
        _ discovery: Result<[OpenAIModelInfo], OpenAIEndpointError>,
        after previous: OpenAIEndpointHealth = OpenAIEndpointHealth(),
        model selected: String? = nil,
        at now: Date = Date()
    ) -> OpenAIEndpointHealth {
        OpenAIHealthEvaluator.evaluate(discovery: discovery, selectedModel: selected ?? model, previous: previous, now: now, latencyMs: 5)
    }

    func testOnlineOfflineOnlineResetsGenerationProof() {
        var ready = evaluate(.success(listed))
        XCTAssertEqual(ready.state, .ready)
        ready.generationVerifiedAt = Date()
        let stillReady = evaluate(.success(listed), after: ready)
        XCTAssertNotNil(stillReady.generationVerifiedAt, "proof survives while online")

        let offline = evaluate(.failure(.unreachable("refused")), after: stillReady)
        XCTAssertEqual(offline.state, .unreachable)
        XCTAssertFalse(offline.state.isOnline)
        XCTAssertNil(offline.generationVerifiedAt)

        let back = evaluate(.success(listed), after: offline)
        XCTAssertEqual(back.state, .ready)
        XCTAssertNil(back.generationVerifiedAt, "a fresh test is needed after an outage")
    }

    func testReachableButNotReadyStates() {
        XCTAssertEqual(evaluate(.failure(.loading("Loading model"))).state, .loading)
        let loadingModel = [OpenAIModelInfo(id: model, contextWindow: nil, vision: nil, status: .loading)]
        XCTAssertEqual(evaluate(.success(loadingModel)).state, .loading)
        XCTAssertEqual(evaluate(.success([])).state, .modelMissing)
        XCTAssertEqual(evaluate(.success(listed), model: "").state, .noModel)
        XCTAssertEqual(evaluate(.success([OpenAIModelInfo(id: "other", contextWindow: nil, vision: nil, status: nil)])).state, .modelMissing)
        XCTAssertEqual(evaluate(.failure(.authFailed)).state, .authFailed)
        XCTAssertTrue(evaluate(.failure(.loading(""))).state.isOnline)
    }

    func testDiscoveryUnsupportedNeedsGenerationProof() {
        let unproven = evaluate(.failure(.discoveryUnsupported))
        XCTAssertEqual(unproven.state, .modelMissing)
        XCTAssertNil(unproven.modelListed)
        var proven = unproven
        proven.generationVerifiedAt = Date()
        XCTAssertEqual(evaluate(.failure(.discoveryUnsupported), after: proven).state, .ready)
    }

    func testBusyStaysOnlineAndStaleIsUnknown() {
        let now = Date()
        let ready = evaluate(.success(listed), at: now)
        XCTAssertEqual(ready.effectiveState(now: now, inFlight: 1), .busy)
        XCTAssertTrue(OpenAIEndpointHealth.State.busy.isOnline)
        XCTAssertEqual(evaluate(.failure(.server(status: 429, message: "slots busy"))).state, .busy)
        XCTAssertEqual(ready.effectiveState(now: now.addingTimeInterval(91), inFlight: 0), .unknown)
        let json = ready.publicJSON(now: now.addingTimeInterval(91))
        XCTAssertEqual(json["state"] as? String, "unknown")
        XCTAssertEqual(json["stale"] as? Bool, true)
        XCTAssertEqual(json["online"] as? Bool, false)
        XCTAssertEqual(OpenAIEndpointHealth().publicJSON()["state"] as? String, "unknown")
    }

    func testPollingBackoff() {
        XCTAssertEqual(OpenAIHealthEvaluator.nextPollDelay(for: .ready, consecutiveFailures: 0), 30)
        XCTAssertEqual(OpenAIHealthEvaluator.nextPollDelay(for: .busy, consecutiveFailures: 0), 30)
        let delays = (1...7).map { OpenAIHealthEvaluator.nextPollDelay(for: .unreachable, consecutiveFailures: $0) }
        XCTAssertEqual(delays, [5, 10, 20, 40, 60, 60, 60])
    }
}
