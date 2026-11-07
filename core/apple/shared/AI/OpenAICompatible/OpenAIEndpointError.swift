import Foundation

/// Every failure the OpenAI-compatible backend can surface. Codes match the
/// device HTTP API contract; messages never contain API keys.
enum OpenAIEndpointError: Error, Equatable, Sendable {
    case invalidURL(String)
    case endpointNotFound
    case unreachable(String)
    case authFailed
    case loading(String)
    case redirectRefused(String)
    case malformedResponse(String)
    case streamTruncated
    case timeout
    case server(status: Int?, message: String)
    case discoveryUnsupported
    case modelNotAvailable(String)
    case noModelSelected
    case toolsUnverified
    case toolsNotSupported
    case visionNotSupported
    case stepLimit(Int)
    case cancelled

    var code: String {
        switch self {
        case .invalidURL: return "INVALID_ENDPOINT_URL"
        case .endpointNotFound: return "ENDPOINT_NOT_FOUND"
        case .unreachable: return "ENDPOINT_UNREACHABLE"
        case .authFailed: return "ENDPOINT_AUTH_FAILED"
        case .loading: return "ENDPOINT_LOADING"
        case .redirectRefused: return "ENDPOINT_REDIRECT_REFUSED"
        case .malformedResponse: return "ENDPOINT_MALFORMED_RESPONSE"
        case .streamTruncated: return "ENDPOINT_STREAM_TRUNCATED"
        case .timeout: return "ENDPOINT_TIMEOUT"
        case .server: return "ENDPOINT_ERROR"
        case .discoveryUnsupported: return "MODEL_DISCOVERY_UNSUPPORTED"
        case .modelNotAvailable: return "MODEL_NOT_AVAILABLE"
        case .noModelSelected: return "NO_MODEL_SELECTED"
        case .toolsUnverified: return "TOOLS_UNVERIFIED"
        case .toolsNotSupported: return "TOOLS_NOT_SUPPORTED"
        case .visionNotSupported: return "VISION_NOT_SUPPORTED"
        case .stepLimit: return "AGENT_STEP_LIMIT"
        case .cancelled: return "INFERENCE_CANCELLED"
        }
    }

    var message: String {
        switch self {
        case .invalidURL(let detail): return detail
        case .endpointNotFound: return "No saved endpoint matches that id or name."
        case .unreachable(let detail): return "The endpoint is unreachable: \(detail)"
        case .authFailed: return "The endpoint rejected the credentials (401/403). Check the API key."
        case .loading(let detail): return detail.isEmpty ? "The server is still loading." : detail
        case .redirectRefused(let target):
            return "The endpoint redirected to another origin (\(target)). Kelpie does not follow cross-origin redirects."
        case .malformedResponse(let detail): return "The endpoint returned a response Kelpie could not parse: \(detail)"
        case .streamTruncated: return "The response stream ended before the model finished."
        case .timeout: return "The endpoint did not respond in time."
        case let .server(status, message):
            return status.map { "The endpoint returned HTTP \($0): \(message)" } ?? "The endpoint reported an error: \(message)"
        case .discoveryUnsupported:
            return "This server does not support model discovery (GET /models). Enter the model ID manually."
        case .modelNotAvailable(let model): return "The server does not list the selected model \"\(model)\"."
        case .noModelSelected: return "Select a model for this endpoint first."
        case .toolsUnverified:
            return "Tool calling is unverified for this model. Run the endpoint test with tools, or declare tool calling in the endpoint settings."
        case .toolsNotSupported: return "This model is configured as not supporting tool calling, so the browser agent cannot run."
        case .visionNotSupported: return "The selected model is text-only; Kelpie will not send it images."
        case .stepLimit(let steps): return "The browser agent stopped after \(steps) tool steps without a final answer."
        case .cancelled: return "Inference was cancelled."
        }
    }

    var response: [String: Any] {
        errorResponse(code: code, message: message)
    }

    /// Server error text reduced to a short, key-free message.
    static func sanitizedServerMessage(_ data: Data, apiKey: String?) -> String {
        var text = String(bytes: data.prefix(4_096), encoding: .utf8) ?? ""
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                text = message
            } else if let message = (object["error"] as? String) ?? (object["message"] as? String) {
                text = message
            }
        }
        return redact(text, apiKey: apiKey)
    }

    static func redact(_ text: String, apiKey: String?) -> String {
        var cleaned = text
        if let apiKey, !apiKey.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: apiKey, with: "[redacted]")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 300 ? String(cleaned.prefix(300)) + "…" : cleaned
    }
}
