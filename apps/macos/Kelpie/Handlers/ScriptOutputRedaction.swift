import Foundation

/// Only the portable core owns matching and typed redaction. Apple retains run-private secret provenance.
enum ScriptOutputRedaction {
    enum Failure: String, Error {
        case invalid = "OUTPUT_REDACTION_INVALID"
        case limit = "OUTPUT_REDACTION_LIMIT"
        case collision = "OUTPUT_REDACTION_COLLISION"
    }

    static func redact(_ outputs: [String: Any], actions: [[String: Any]], secrets: [String]) throws -> [String: Any] {
        let extractionNames = actions.filter { $0["action"] as? String == "extract" }.compactMap { $0["name"] as? String }
        let request: [String: Any] = ["outputs": outputs, "extractionNames": extractionNames, "secrets": secrets]
        guard JSONSerialization.isValidJSONObject(request),
              let data = try? JSONSerialization.data(withJSONObject: request),
              data.count <= 5_242_880,
              let text = String(data: data, encoding: .utf8),
              let pointer = text.withCString({ kelpie_script_redact_outputs_json($0) }) else { throw Failure.limit }
        defer { kelpie_script_redaction_free_string(pointer) }
        let response = Data(String(cString: pointer).utf8)
        guard response.count <= 1_048_576,
              let value = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw Failure.limit }
        if value["ok"] as? Bool == true, let result = value["outputs"] as? [String: Any] { return result }
        let code = (value["error"] as? [String: Any])?["code"] as? String
        throw code.flatMap(Failure.init(rawValue:)) ?? Failure.limit
    }
}
