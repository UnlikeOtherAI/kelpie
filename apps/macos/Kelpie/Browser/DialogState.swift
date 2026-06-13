import Foundation

/// Tracks pending JavaScript dialogs (alert/confirm/prompt) from WKWebView.
///
/// A single shared instance mirrors iOS, where every WebView coordinator and the
/// handler read the one `HandlerContext.dialogState`. On macOS renderers are
/// created per-tab and decoupled from the handler context, so the renderer's
/// WKUIDelegate enqueues into this shared store and `BrowserManagementHandler`
/// reads the same instance.
@MainActor
final class DialogState {

    /// The process-wide dialog store shared by the active WebKit renderer and the
    /// browser-management handler.
    static let shared = DialogState()

    enum DialogType: String {
        case alert
        case confirm
        case prompt
    }

    struct PendingDialog {
        let type: DialogType
        let message: String
        let defaultText: String?
        let completion: (String?) -> Void  // nil = dismiss, non-nil = accept
    }

    /// The dialog currently waiting for a response, or nil if none is showing.
    private(set) var current: PendingDialog?

    /// Auto-handler mode: nil = queue dialogs for manual handling,
    /// "accept" = auto-accept, "dismiss" = auto-dismiss.
    var autoHandler: String?

    /// Default text to send for prompt dialogs when auto-accepting.
    var autoPromptText: String = ""

    /// Enqueue a dialog. If autoHandler is set, resolve immediately; otherwise hold it as current.
    func enqueue(_ dialog: PendingDialog) {
        if let mode = autoHandler {
            resolve(dialog, action: mode)
            return
        }
        // If a dialog is already pending, dismiss it to avoid hanging the WebView.
        if let existing = current {
            existing.completion(nil)
        }
        current = dialog
    }

    /// Handle the current dialog with an explicit action.
    func handle(action: String, text: String? = nil) -> (type: DialogType, handled: Bool) {
        guard let dialog = current else {
            return (.alert, false)
        }
        current = nil
        if action == "accept" {
            let responseText: String
            if dialog.type == .prompt {
                responseText = text ?? dialog.defaultText ?? ""
            } else {
                responseText = ""
            }
            dialog.completion(responseText)
        } else {
            dialog.completion(nil)
        }
        return (dialog.type, true)
    }

    // MARK: - Private

    private func resolve(_ dialog: PendingDialog, action: String) {
        if action == "accept" {
            let responseText: String
            if dialog.type == .prompt {
                responseText = autoPromptText.isEmpty ? (dialog.defaultText ?? "") : autoPromptText
            } else {
                responseText = ""
            }
            dialog.completion(responseText)
        } else {
            dialog.completion(nil)
        }
    }
}
