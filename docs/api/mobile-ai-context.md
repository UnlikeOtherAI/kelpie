# Mobile AI page context and conversation

The iOS and Android inference API keeps the same contract on both platforms. It adds no chat controls or server-owned conversation store. Callers own conversation history and send the complete `messages` array on each `ai-infer` request. History remains subject to the selected model's context window; Kelpie does not silently truncate it to a fixed turn count.

`messages` accepts `system`, `user` and `assistant` roles with string content. Malformed turns return `INVALID_PARAM` rather than disappearing from the conversation. Native GGUF receives the full role messages and uses its model chat template. Ollama receives `/api/chat` role messages. Platform text inference receives the full conversation as role/content JSON alongside the current request and page evidence.

`context: "page_text"`, `"dom"` and `"accessibility"` read the requested `tabId`, or capture the currently visible tab when omitted. Reading an existing background tab does not switch the visible tab. The page-text snapshot contains the title, URL, body text and accessible names, including visible image alt text, ARIA labels/labelled-by text and SVG titles. Page evidence is untrusted data and cannot grant permission to perform actions. The body is bounded separately from accessible names so long pages do not erase logo labels.

Page extraction errors and nonexistent tabs fail explicitly before inference. An empty page is a successful empty snapshot, distinct from an invalid JavaScript result. Switching tabs during any pending page-context snapshot cannot redirect the read into another tab. Existing action/tool runs remain restricted to their pinned visible tab; changing the visible tab stops further tool calls.

The `get-page-text` response retains its existing fields and adds `url` and `accessibleLabels`. It now honors `tabId` on both mobile platforms and reports malformed snapshot results as `EVAL_ERROR`.

Focused regressions cover full history beyond ten turns, malformed history, bounded text with accessible names, requested background tabs, hidden labels, nonexistent tabs and failed extraction. iOS fixtures run in real WKWebViews; Android JVM tests exercise snapshot decoding and the inference-context error boundary.
