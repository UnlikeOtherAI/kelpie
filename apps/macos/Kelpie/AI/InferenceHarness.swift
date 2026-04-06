import AppKit
import Foundation

struct InferenceHarness {
    private let engine = InferenceEngine.shared
    private let context: HandlerContext
    private let maxRounds = 3
    private let toolTokenBudget = 1500

    init(context: HandlerContext) {
        self.context = context
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
        let summary = await PageSummary.gather(from: context)
        var totalTokens = 0
        var toolCallsMade = 0
        var rounds = 0
        var transcript: [String] = []
        var transcription: String?
        var pendingImage: Data?

        if let preloadedContext {
            let fullPrompt = buildDirectAnswerPrompt(
                userPrompt: prompt,
                pageSummary: summary.formatted(),
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
                pageSummary: summary.formatted(),
                preloadedContext: nil,
                transcript: transcript
            )
            let inference = try await engine.infer(prompt: fullPrompt, audio: audio, image: pendingImage)
            totalTokens += inference.tokensUsed
            if audio != nil {
                transcription = transcription ?? extractTranscription(from: inference.text)
            }

            if let toolCall = parseToolCall(from: inference.text) {
                rounds += 1
                toolCallsMade += 1

                if toolCall.name == "get_screenshot" {
                    pendingImage = try await captureScreenshot()
                    transcript.append("Tool get_screenshot returned: Screenshot captured and attached.")
                    continue
                }

                let toolResult = await executeTool(toolCall.name, args: toolCall.args)
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

    @MainActor
    // swiftlint:disable:next function_body_length
    func executeTool(_ name: String, args: [String: String]) async -> String {
        let payload: Any

        switch name {
        case "get_text":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var el = document.body || document.documentElement;
                    var text = (el?.innerText || el?.textContent || '').trim();
                    return {
                        title: document.title || '',
                        content: text,
                        wordCount: text ? text.split(/\\s+/).length : 0
                    };
                })()
                """
            )) ?? [:]

        case "get_dom":
            // swiftlint:disable:next force_unwrapping
            let selector = (args["selector"]?.isEmpty == false) ? args["selector"]! : "body"
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var el = document.querySelector('\(escapeForJavaScript(selector))');
                    if (!el) return { found: false };
                    return {
                        found: true,
                        selector: '\(escapeForJavaScript(selector))',
                        html: el.outerHTML,
                        nodeCount: el.querySelectorAll('*').length + 1
                    };
                })()
                """
            )) ?? [:]

        case "get_element":
            let selector = args["selector"] ?? ""
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var el = document.querySelector('\(escapeForJavaScript(selector))');
                    if (!el) return { found: false };
                    var attrs = {};
                    for (var i = 0; i < el.attributes.length; i++) {
                        attrs[el.attributes[i].name] = el.attributes[i].value;
                    }
                    return {
                        found: true,
                        selector: '\(escapeForJavaScript(selector))',
                        text: (el.textContent || '').trim(),
                        attributes: attrs
                    };
                })()
                """
            )) ?? [:]

        case "find_element":
            let text = args["text"] ?? ""
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var wanted = '\(escapeForJavaScript(text))'.toLowerCase();
                    var all = document.querySelectorAll('*');
                    for (var el of all) {
                        var content = (el.textContent || '').trim();
                        if (!content || !content.toLowerCase().includes(wanted)) continue;
                        var rect = el.getBoundingClientRect();
                        if (rect.width <= 0 || rect.height <= 0) continue;
                        return {
                            found: true,
                            element: {
                                tag: el.tagName.toLowerCase(),
                                selector: el.tagName.toLowerCase() + (el.id ? '#' + el.id : ''),
                                text: content.substring(0, 200)
                            }
                        };
                    }
                    return { found: false };
                })()
                """
            )) ?? [:]

        case "get_forms":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var forms = document.querySelectorAll('form');
                    return {
                        formCount: forms.length,
                        forms: Array.from(forms).map(function(form, index) {
                            return {
                                selector: 'form:nth-of-type(' + (index + 1) + ')',
                                fields: Array.from(form.querySelectorAll('input,select,textarea')).map(function(el) {
                                    return {
                                        name: el.name || '',
                                        type: el.type || el.tagName.toLowerCase(),
                                        value: el.value || '',
                                        required: !!el.required
                                    };
                                })
                            };
                        })
                    };
                })()
                """
            )) ?? [:]

        case "get_errors":
            let errors = context.consoleMessages.filter { ($0["level"] as? String) == "error" }
            payload = ["count": errors.count, "errors": Array(errors.suffix(20))]

        case "get_console":
            payload = [
                "count": context.consoleMessages.count,
                "messages": Array(context.consoleMessages.suffix(20))
            ]

        case "get_network":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var entries = performance.getEntriesByType('navigation').concat(
                        performance.getEntriesByType('resource')
                    );
                    var recent = entries.slice(Math.max(0, entries.length - 20));
                    return {
                        count: entries.length,
                        entries: recent.map(function(entry) {
                            return {
                                url: entry.name,
                                initiator: entry.initiatorType || entry.entryType,
                                duration: Math.round(entry.duration || 0)
                            };
                        })
                    };
                })()
                """
            )) ?? [:]

        case "get_cookies":
            let cookies = await context.allCookies().map { cookie in
                [
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path
                ]
            }
            payload = ["count": cookies.count, "cookies": cookies]

        case "get_storage":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var entries = {};
                    for (var i = 0; i < localStorage.length; i++) {
                        var key = localStorage.key(i);
                        entries[key] = localStorage.getItem(key);
                    }
                    return { count: localStorage.length, entries: entries };
                })()
                """
            )) ?? [:]

        case "get_links":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var links = Array.from(document.querySelectorAll('a[href]')).slice(0, 200);
                    return {
                        count: links.length,
                        links: links.map(function(link) {
                            return {
                                href: link.href,
                                text: (link.textContent || '').trim().substring(0, 200)
                            };
                        })
                    };
                })()
                """
            )) ?? [:]

        case "get_visible":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    var elements = [];
                    var all = document.querySelectorAll('a,button,input,select,textarea,[role="button"],[role="link"]');
                    for (var el of all) {
                        var rect = el.getBoundingClientRect();
                        if (rect.width <= 0 || rect.height <= 0) continue;
                        if (rect.bottom <= 0 || rect.right <= 0 || rect.top >= window.innerHeight || rect.left >= window.innerWidth) continue;
                        elements.push({
                            tag: el.tagName.toLowerCase(),
                            text: (el.textContent || el.value || '').trim().substring(0, 120),
                            role: el.getAttribute('role') || '',
                            selector: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '')
                        });
                        if (elements.length >= 100) break;
                    }
                    return { count: elements.length, elements: elements };
                })()
                """
            )) ?? [:]

        case "get_a11y":
            payload = (try? await context.evaluateJSReturningJSON(
                """
                (function() {
                    function walk(node, depth) {
                        if (!node || depth > 3) return null;
                        var item = {
                            role: node.getAttribute('role') || node.tagName.toLowerCase(),
                            name: (node.getAttribute('aria-label') || node.textContent || '').trim().substring(0, 80)
                        };
                        var children = [];
                        for (var child of node.children) {
                            var result = walk(child, depth + 1);
                            if (result) children.push(result);
                        }
                        if (children.length) item.children = children;
                        return item;
                    }
                    return { tree: walk(document.body, 0) };
                })()
                """
            )) ?? [:]

        default:
            payload = ["error": "Unknown tool: \(name)"]
        }

        return truncate(stringify(payload), maxTokens: toolTokenBudget)
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
        transcript: [String]
    ) -> String {
        var sections = [SystemPrompt.build(), "", pageSummary]
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

    private func parseToolCall(from text: String) -> (name: String, args: [String: String])? {
        guard let object = parseJSONObject(from: text),
              let tool = object["tool"] as? String else {
            return nil
        }
        let args = (object["args"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) { result, entry in
            if let stringValue = entry.value as? String {
                result[entry.key] = stringValue
            } else {
                result[entry.key] = String(describing: entry.value)
            }
        }
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

    private func captureScreenshot() async throws -> Data {
        let image = try await context.takeSnapshot()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw HandlerError.platformNotSupported("Failed to encode screenshot")
        }
        return png
    }

    private func stringify(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func escapeForJavaScript(_ value: String) -> String {
        JSEscape.string(value)
    }

    private func elapsedMs(since startedAt: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000)
    }
}
