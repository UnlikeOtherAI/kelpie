import AppKit
import Foundation
struct InferenceHarness {
    private let engine = InferenceEngine.shared
    private let context: HandlerContext
    private let router: Router?
    private let maxRounds = 3
    private let toolTokenBudget = 1500

    init(context: HandlerContext, router: Router?) {
        self.context = context
        self.router = router
    }

    struct Result {
        let answer: String
        let references: [Reference]
        let toolCallsMade: Int
        let totalTokens: Int
        let totalTimeMs: Int
        let transcription: String?
    }

    struct Reference {
        let type: String
        let selector: String?
        let message: String?
        let description: String?
    }

    func run(prompt: String, audio: Data? = nil, preloadedContext: String? = nil) async throws -> Result {
        let startedAt = DispatchTime.now()
        var totalTokens = 0
        var toolCallsMade = 0
        var rounds = 0
        var transcript: [String] = []
        var transcription: String?
        var pendingImage: Data?
        let vision = await MainActor.run { engine.capabilities.contains("vision") }
        guard let router else { throw InferenceEngine.InferenceError.inferenceFailed("Browser router is unavailable") }
        let tabId = await MainActor.run { context.activeEngineIsChromium ? "chromium" : context.tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString }
        let browser = await router.makeBrowserGateway(allowActions: false, pinnedTabId: tabId, agent: true, admission: .localReadOnly(vision: vision))
        let definitions = await browser.toolDefinitions()
        let observation = await browser.request(["version": 1, "method": "tab.snapshot", "tabId": tabId ?? "",
                                                 "params": ["maxChars": 1200, "maxElements": 1]])
        guard observation["ok"] as? Bool == true, let value = observation["value"] as? [String: Any] else {
            throw InferenceEngine.InferenceError.inferenceFailed("Could not observe the pinned browser tab")
        }
        let summary = "Untrusted page metadata: " + stringify(["title": value["title"] ?? "", "url": value["url"] ?? ""])

        if let preloadedContext {
            let fullPrompt = buildDirectAnswerPrompt(
                userPrompt: prompt,
                pageSummary: summary,
                pageText: preloadedContext
            )
            let inference = try await engine.infer(prompt: fullPrompt, audio: audio, image: nil)
            totalTokens += inference.tokensUsed
            let answer = inference.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(
                answer: answer.isEmpty ? "No response." : answer,
                references: [],
                toolCallsMade: 0,
                totalTokens: totalTokens,
                totalTimeMs: elapsedMs(since: startedAt),
                transcription: transcription
            )
        }

        while rounds < maxRounds {
            let fullPrompt = buildPrompt(
                userPrompt: prompt,
                pageSummary: summary,
                preloadedContext: nil,
                transcript: transcript,
                toolDefinitions: stringify(definitions)
            )
            let inference = try await engine.infer(prompt: fullPrompt, audio: audio, image: pendingImage)
            totalTokens += inference.tokensUsed
            if audio != nil {
                transcription = transcription ?? extractTranscription(from: inference.text)
            }

            if let toolCall = parseToolCall(from: inference.text) {
                rounds += 1
                toolCallsMade += 1

                let result = await browser.callTool(name: toolCall.name, arguments: toolCall.args)
                try refuseUncertainOutcome(result)
                let observation = BrowserModelObservation(result, vision: vision)
                if let image = observation.image { pendingImage = image }
                let toolResult = truncate(stringify(observation.text), maxTokens: toolTokenBudget)
                transcript.append("Tool \(toolCall.name) returned: \(toolResult)")
                continue
            }

            let parsed = parseFinalAnswer(from: inference.text)
            return Result(
                answer: parsed.answer,
                references: parsed.references,
                toolCallsMade: toolCallsMade,
                totalTokens: totalTokens,
                totalTimeMs: elapsedMs(since: startedAt),
                transcription: transcription
            )
        }

        return Result(
            answer: "I need more page data than I can safely gather in one pass.",
            references: [],
            toolCallsMade: toolCallsMade,
            totalTokens: totalTokens,
            totalTimeMs: elapsedMs(since: startedAt),
            transcription: transcription
        )
    }

    private func refuseUncertainOutcome(_ result: [String: Any]) throws {
        let canonical = BrowserControlGateway.canonicalResult(result)
        if (canonical["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool == true {
            throw InferenceEngine.InferenceError.inferenceFailed("Browser outcome is uncertain; the model turn stopped without retrying")
        }
    }

    private func truncate(_ text: String, maxTokens: Int) -> String {
        let maxCharacters = max(1, maxTokens * 4)
        guard text.count > maxCharacters else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        return text[..<endIndex] + "... [truncated, \(text.count) chars total]"
    }

    private func buildDirectAnswerPrompt(userPrompt: String, pageSummary: String, pageText: String) -> String {
        """
        You are a browser assistant. Answer the user's question based ONLY on the page content below.
        Be concise. Do not make up information not present in the content.

        \(pageSummary)

        Page content:
        \(pageText)

        Question: \(userPrompt)
        Answer:
        """
    }

    private func buildPrompt(
        userPrompt: String,
        pageSummary: String,
        preloadedContext: String?,
        transcript: [String],
        toolDefinitions: String
    ) -> String {
        var sections = [SystemPrompt.build(tools: toolDefinitions), "", pageSummary]
        if let preloadedContext, !preloadedContext.isEmpty {
            sections.append("")
            sections.append("Context:")
            sections.append(preloadedContext)
        }
        if !transcript.isEmpty {
            sections.append("")
            sections.append("Tool history:")
            sections.append(transcript.joined(separator: "\n"))
        }
        sections.append("")
        sections.append("User question:")
        sections.append(userPrompt)
        return sections.joined(separator: "\n")
    }

    private func parseToolCall(from text: String) -> (name: String, args: [String: Any])? {
        guard let object = parseJSONObject(from: text),
              let tool = object["tool"] as? String else {
            return nil
        }
        let args = object["args"] as? [String: Any] ?? [:]
        return (tool, args)
    }

    private func parseFinalAnswer(from text: String) -> (answer: String, references: [Reference]) {
        guard let object = parseJSONObject(from: text) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }
        let answer = (object["answer"] as? String) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        let references = (object["references"] as? [[String: Any]] ?? []).map {
            Reference(
                type: $0["type"] as? String ?? "unknown",
                selector: $0["selector"] as? String,
                message: $0["message"] as? String,
                description: $0["description"] as? String
            )
        }
        return (answer, references)
    }

    private func parseJSONObject(from text: String) -> [String: Any]? {
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var prevWasBackslash = false
        for i in text.indices[startIdx...] {
            let ch = text[i]
            if inString {
                if ch == "\\" && !prevWasBackslash {
                    prevWasBackslash = true
                    continue
                }
                if ch == "\"" && !prevWasBackslash { inString = false }
                prevWasBackslash = false
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let json = String(text[startIdx...i])
                    guard let data = json.data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                }
            default: break
            }
        }
        return nil
    }

    private func extractTranscription(from text: String) -> String? {
        parseJSONObject(from: text)?["transcription"] as? String
    }

    private func stringify(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func elapsedMs(since startedAt: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000)
    }
}
