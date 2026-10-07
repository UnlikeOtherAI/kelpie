import Foundation

/// One entry from `GET {base}/models`, keeping only metadata the server
/// actually returned. Unknown values stay `nil`.
struct OpenAIModelInfo: Equatable, Sendable {
    enum Status: String, Sendable {
        case loaded
        case loading
        case unloaded
    }

    let id: String
    let contextWindow: Int?
    let vision: Bool?
    let status: Status?

    var publicJSON: [String: Any] {
        var json: [String: Any] = ["id": id]
        json["contextWindow"] = contextWindow ?? NSNull()
        json["vision"] = vision ?? NSNull()
        json["status"] = status?.rawValue ?? NSNull()
        return json
    }
}

enum OpenAIModelListParser {
    enum ParseError: Error, Equatable {
        case notJSON
        case wrongShape
    }

    /// Parses `{"data":[…]}` or `{"models":[…]}`. Entries without a string
    /// `id` are skipped; an empty list is valid.
    static func parse(_ data: Data) throws -> [OpenAIModelInfo] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw ParseError.notJSON }
        guard let root = object as? [String: Any],
              let entries = (root["data"] ?? root["models"]) as? [Any] else {
            throw ParseError.wrongShape
        }
        return entries.compactMap { entry in
            guard let raw = entry as? [String: Any],
                  let id = raw["id"] as? String,
                  !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return OpenAIModelInfo(
                id: id,
                contextWindow: contextWindow(in: raw),
                vision: vision(in: raw),
                status: status(in: raw)
            )
        }
    }

    private static func contextWindow(in raw: [String: Any]) -> Int? {
        let meta = raw["meta"] as? [String: Any]
        let candidates: [Any?] = [
            meta?["n_ctx"],
            raw["context_length"],
            raw["max_model_len"],
            raw["loaded_context_length"],
            raw["max_context_length"],
            raw["context_window"]
        ]
        for candidate in candidates {
            if let value = positiveInt(candidate) { return value }
        }
        return nil
    }

    private static func vision(in raw: [String: Any]) -> Bool? {
        if let architecture = raw["architecture"] as? [String: Any],
           let modalities = architecture["input_modalities"] as? [String] {
            return modalities.contains { $0.lowercased() == "image" }
        }
        if let capabilities = raw["capabilities"] as? [String], capabilities.contains(where: { $0.lowercased() == "vision" }) {
            return true
        }
        return nil
    }

    private static func status(in raw: [String: Any]) -> OpenAIModelInfo.Status? {
        let text: String?
        if let nested = raw["status"] as? [String: Any] {
            text = nested["value"] as? String
        } else {
            text = (raw["status"] as? String) ?? (raw["state"] as? String)
        }
        switch text?.lowercased() {
        case "loaded", "ready": return .loaded
        case "loading": return .loading
        case "unloaded", "not-loaded", "not_loaded": return .unloaded
        default: return nil
        }
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, number.intValue > 0 { return number.intValue }
        if let string = value as? String, let parsed = Int(string), parsed > 0 { return parsed }
        return nil
    }
}
