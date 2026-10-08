import XCTest
@testable import Kelpie

final class LocalInferenceTests: XCTestCase {
    func testNativeBridgeRejectsMissingModelAndAgentMode() async {
        let engine = LocalInference.shared
        _ = await engine.execute("unload")
        let missing = await engine.load(["model": "/missing.gguf"])
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? String, "MODEL_NOT_FOUND")
        let agent = await engine.execute("infer", body: ["prompt": "hello", "agent": true])
        XCTAssertEqual((agent["error"] as? [String: Any])?["code"] as? String, "TOOLS_NOT_SUPPORTED")
    }

    /// Supply a user-owned GGUF in the test host's Documents directory to run the real bridge.
    func testRealGGUFWhenProvided() async throws {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inference-test.gguf")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("No inference-test.gguf fixture supplied") }
        let engine = LocalInference.shared
        let loaded = await engine.load(["model": file.path])
        XCTAssertEqual(loaded["success"] as? Bool, true)
        let answer = await engine.execute("infer", body: ["prompt": "Say hello in one sentence.", "maxTokens": 32, "temperature": 0])
        XCTAssertEqual(answer["success"] as? Bool, true)
        XCTAssertFalse((answer["response"] as? String ?? "").isEmpty)
        let unloaded = await engine.execute("unload")
        XCTAssertEqual(unloaded["loaded"] as? Bool, false)
    }
}
