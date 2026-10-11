import Foundation

/// Keeps one authorized model image separate from the bounded textual observation.
struct BrowserModelObservation {
    let text: [String: Any]
    let image: Data?

    init(_ result: [String: Any], vision: Bool) {
        var canonical = BrowserControlGateway.canonicalResult(result)
        var value = canonical["value"] as? [String: Any] ?? [:]
        let content = result["content"] as? [[String: Any]] ?? []
        let attachment = content.first { $0["type"] as? String == "image" }
        let encoded = attachment?["data"] as? String ?? value["image"] as? String ?? value["data"] as? String
        image = vision ? encoded.flatMap { Data(base64Encoded: $0) } : nil
        value.removeValue(forKey: "image")
        value.removeValue(forKey: "data")
        if encoded != nil { value["imageAttached"] = image != nil }
        if canonical["value"] is [String: Any] { canonical["value"] = value }
        text = canonical.isEmpty ? result : canonical
    }
}
