import Foundation

/// Fixed public diagnostics shared by Apple capture adapters.
enum ScriptCaptureError: LocalizedError {
    case image, budget, viewport, document, duration, cancelled
    var errorDescription: String? {
        switch self {
        case .image: return "Unable to encode capture frame"
        case .budget: return "CAPTURE_BUDGET_EXCEEDED: capture storage limit reached"
        case .viewport: return "CAPTURE_VIEWPORT_CHANGED: viewport changed during capture"
        case .document: return "CAPTURE_DOCUMENT_CHANGED: document changed while taking a frame"
        case .cancelled: return "CAPTURE_CANCELLED: capture finalization stopped"
        case .duration: return "CAPTURE_DURATION_EXCEEDED: capture duration limit reached"
        }
    }
}
