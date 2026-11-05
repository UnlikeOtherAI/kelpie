import Foundation

/// Product scripts own their run gate. Other browser mutations retain the persistent browser lease.
enum ScriptGatewayPolicy {
    static let controls: Set<String> = ["abort-script", "get-script-status", "get-script-artifact"]

    static func independent(method: String, body: [String: Any]) -> Bool {
        controls.contains(method) || (method == "play-script" && body["version"] != nil)
    }

    static func independentMCPMethod(_ rpc: [String: Any], resolvedMethod: String?) -> String? {
        guard rpc["method"] as? String == "tools/call", let resolvedMethod,
              let params = rpc["params"] as? [String: Any] else { return nil }
        var arguments = params["arguments"] as? [String: Any] ?? [:]
        if params["name"] as? String == "kelpie_extension" {
            arguments = arguments["arguments"] as? [String: Any] ?? [:]
        }
        return independent(method: resolvedMethod, body: arguments) ? resolvedMethod : nil
    }

    @MainActor
    static func mutationFailure(
        method: String,
        mutates: Bool,
        recordingError: @MainActor () -> [String: Any]?,
        rendererAllowed: @MainActor () -> Bool
    ) -> [String: Any]? {
        guard mutates, !controls.contains(method) else { return nil }
        if let failure = recordingError() { return failure }
        guard rendererAllowed() else {
            return ["success": false, "mayHaveCompleted": false,
                    "error": ["code": "INPUT_UNCERTAIN", "message": "The owned renderer still has a pending operation"]]
        }
        return nil
    }

    static func timeoutNanoseconds(method: String) -> UInt64 {
        method == "play-script" ? 360_000_000_000 : 30_000_000_000
    }
}
