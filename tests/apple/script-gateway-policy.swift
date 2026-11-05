import Foundation

func successResponse(_ values: [String: Any]) -> [String: Any] { values.merging(["success": true]) { _, new in new } }
func errorResponse(code: String, message: String) -> [String: Any] { ["success": false, "error": ["code": code, "message": message]] }

@main
struct ScriptGatewayPolicyAcceptance {
    static func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw NSError(domain: "ScriptGatewayPolicyAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    }

    static func rpc(_ name: String, arguments: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
    }

    @MainActor
    static func main() throws {
        try require(!ScriptGatewayPolicy.independent(method: "play-script", body: ["actions": []]), "Legacy play keeps existing serialization")
        for version: Any in [1, "1", NSNull()] {
            try require(ScriptGatewayPolicy.independent(method: "play-script", body: ["version": version]), "Every version-present play reaches strict admission")
        }
        for method in ["abort-script", "get-script-status", "get-script-artifact"] {
            try require(ScriptGatewayPolicy.independent(method: method, body: [:]), "Owner-checked control remains responsive")
        }
        for method in ["navigate", "browser-control-evaluate", "fill", "tap", "new-tab", "eval", "ai-infer"] {
            try require(!ScriptGatewayPolicy.independent(method: method, body: ["version": 1]), "No unrelated mutation bypass")
        }
        let direct = rpc("kelpie_play_script", arguments: ["version": 1])
        try require(ScriptGatewayPolicy.independentMCPMethod(direct, resolvedMethod: "play-script") == "play-script", "Named strict MCP route")
        let generic = rpc("kelpie_extension", arguments: ["name": "kelpie_play_script", "arguments": ["version": 1]])
        try require(ScriptGatewayPolicy.independentMCPMethod(generic, resolvedMethod: "play-script") == "play-script", "Generic strict MCP route")
        let legacy = rpc("kelpie_extension", arguments: ["name": "kelpie_play_script", "arguments": ["actions": []]])
        try require(ScriptGatewayPolicy.independentMCPMethod(legacy, resolvedMethod: "play-script") == nil, "Legacy generic MCP retains persistent lease")
        let nestedWrong = rpc("kelpie_extension", arguments: ["name": "kelpie_play_script", "version": 1, "arguments": [:]])
        try require(ScriptGatewayPolicy.independentMCPMethod(nestedWrong, resolvedMethod: "play-script") == nil, "Outer envelope cannot fabricate strict version")
        try require(ScriptGatewayPolicy.independentMCPMethod(direct, resolvedMethod: nil) == nil, "Unregistered extension cannot acquire independent gateway")
        try require(ScriptGatewayPolicy.independentMCPMethod(["method": "tools/list"], resolvedMethod: "abort-script") == nil, "Discovery cannot dispatch a control")
        try require(ScriptGatewayPolicy.timeoutNanoseconds(method: "play-script") == 360_000_000_000, "Strict playback transport grace")
        try require(ScriptGatewayPolicy.timeoutNanoseconds(method: "get-script-status") == 30_000_000_000, "Controls keep short transport budget")
        let recordingFailure: [String: Any] = ["success": false, "error": ["code": "RECORDING_IN_PROGRESS", "message": "Script is playing"]]
        let blocked = ScriptGatewayPolicy.mutationFailure(method: "browser-control-evaluate", mutates: true,
                                                          recordingError: { recordingFailure }, rendererAllowed: { true })
        try require((blocked?["error"] as? [String: Any])?["code"] as? String == "RECORDING_IN_PROGRESS", "Fixed mutating reader cannot bypass recording gate")
        let retired = ScriptGatewayPolicy.mutationFailure(method: "play-script", mutates: true,
                                                          recordingError: { nil }, rendererAllowed: { false })
        try require((retired?["error"] as? [String: Any])?["code"] as? String == "INPUT_UNCERTAIN", "Retiring renderer refuses new mutation")
        for method in ScriptGatewayPolicy.controls {
            let control = ScriptGatewayPolicy.mutationFailure(method: method, mutates: true,
                                                               recordingError: { recordingFailure }, rendererAllowed: { false })
            try require(control == nil, "Owner-checked control reaches native authority while a run is active")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("private.png")
        try Data([0, 1, 2, 3]).write(to: file, options: .withoutOverwriting)
        let store = ScriptArtifactStore()
        let artifact = try store.add(url: file, runID: "run-A", mimeType: "image/png", owner: "owner-A",
                                     extra: ["width": 1, "height": 1])
        let request: [String: Any] = ["runId": "run-A", "artifactId": artifact["id"] ?? ""]
        let denied = store.read(request, owner: "owner-B")
        try require((denied["error"] as? [String: Any])?["code"] as? String == "ARTIFACT_NOT_FOUND" && denied["data"] == nil,
                    "Independent artifact control cannot bypass owner denial")
        let allowed = store.read(request, owner: "owner-A")
        try require(allowed["success"] as? Bool == true && allowed["data"] as? String == "AAECAw==", "Same owner can still read through independent control")
        print("PASS shared Apple script gateway classification: strict/legacy, named/generic, controls, unrelated mutations, timeout scopes")
    }
}
