import XCTest
@testable import Kelpie

final class OpenAIStreamingTests: XCTestCase {
    // MARK: - SSE parser

    private func parseAll(_ data: Data, chunkSizes: () -> Int) -> [ServerSentEvent] {
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let end = min(bytes.count, index + max(1, chunkSizes()))
            events += parser.feed(bytes[index..<end])
            index = end
        }
        return events + parser.finish()
    }

    func testParserIsIndependentOfChunkBoundaries() {
        let text = "data: {\"a\":\"čeština 🚀\"}\r\n\r\n: keep-alive\n\nevent: ping\ndata: line1\ndata: line2\r\rdata: [DONE]\n\n"
        let data = Data(text.utf8)
        let whole = parseAll(data) { Int.max }
        XCTAssertEqual(whole, [
            ServerSentEvent(event: nil, data: "{\"a\":\"čeština 🚀\"}"),
            ServerSentEvent(event: "ping", data: "line1\nline2"),
            ServerSentEvent(event: nil, data: "[DONE]")
        ])
        XCTAssertEqual(parseAll(data) { 1 }, whole, "byte-by-byte must match (splits UTF-8 and CRLF)")
        for _ in 0..<50 {
            XCTAssertEqual(parseAll(data) { Int.random(in: 1...6) }, whole)
        }
    }

    func testParserFlushesFinalEventWithoutTrailingBlankLine() {
        var parser = ServerSentEventParser()
        XCTAssertTrue(parser.feed(Array("data: [DONE]".utf8)).isEmpty)
        XCTAssertEqual(parser.finish(), [ServerSentEvent(event: nil, data: "[DONE]")])
    }

    func testParserIgnoresCommentsAndFieldsWithoutData() {
        var parser = ServerSentEventParser()
        let events = parser.feed(Array(": comment\nid: 7\nretry: 100\n\n".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Accumulator

    func testAccumulatorKeepsReasoningApartAndIgnoresRoleOnlyDeltas() throws {
        var accumulator = OpenAIChatAccumulator()
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["role": "assistant", "content": ""]))
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["reasoning_content": "Think "]))
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["reasoning": "more."]))
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["content": "Hello"]))
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["content": " world"], finish: "stop"))
        try accumulator.apply(chunk: ["choices": [], "usage": ["prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5]])
        XCTAssertTrue(try accumulator.apply(eventData: "[DONE]"))
        let result = accumulator.result()
        XCTAssertEqual(result.content, "Hello world")
        XCTAssertEqual(result.reasoning, "Think more.")
        XCTAssertEqual(result.finishReason, "stop")
        XCTAssertEqual(result.usage, OpenAIUsage(promptTokens: 3, completionTokens: 2, totalTokens: 5))
        XCTAssertTrue(result.toolCalls.isEmpty)
    }

    func testAccumulatorAssemblesFragmentedParallelToolCalls() throws {
        var accumulator = OpenAIChatAccumulator()
        let fragments: [[String: Any]] = [
            ["index": 0, "id": "call_a", "type": "function", "function": ["name": "fi", "arguments": ""]],
            ["index": 1, "id": "call_b", "type": "function", "function": ["name": "click", "arguments": "{\"sel"]],
            ["index": 0, "function": ["name": "ll", "arguments": "{\"selector\": \"#na"]],
            ["index": 0, "function": ["arguments": "me\", \"value\": \"Ada \\u00e9\"}"]],
            ["index": 1, "function": ["arguments": "ector\":\"#go\"}"]]
        ]
        for fragment in fragments {
            try accumulator.apply(chunk: OpenAIFixtures.chunk(["tool_calls": [fragment]]))
        }
        try accumulator.apply(chunk: OpenAIFixtures.chunk([:], finish: "tool_calls"))
        let calls = accumulator.result().toolCalls
        XCTAssertEqual(calls.map(\.id), ["call_a", "call_b"])
        XCTAssertEqual(calls.map(\.name), ["fill", "click"])
        XCTAssertEqual(calls[0].parsedArguments?["value"] as? String, "Ada é")
        XCTAssertEqual(calls[1].parsedArguments?["selector"] as? String, "#go")
    }

    func testInvalidToolArgumentsAreReportedNotCrashing() throws {
        var accumulator = OpenAIChatAccumulator()
        try accumulator.apply(chunk: OpenAIFixtures.chunk(["tool_calls": [["index": 0, "id": "x", "function": ["name": "click", "arguments": "{\"selector\":"]]]]))
        let call = try XCTUnwrap(accumulator.result().toolCalls.first)
        XCTAssertNil(call.parsedArguments)
    }

    func testErrorFramesAndMalformedEventsThrow() {
        var accumulator = OpenAIChatAccumulator()
        XCTAssertThrowsError(try accumulator.apply(eventData: "{\"error\":{\"message\":\"model crashed\"}}")) { error in
            XCTAssertEqual((error as? OpenAIEndpointError)?.code, "ENDPOINT_ERROR")
        }
        XCTAssertThrowsError(try accumulator.apply(eventData: "not json")) { error in
            XCTAssertEqual((error as? OpenAIEndpointError)?.code, "ENDPOINT_MALFORMED_RESPONSE")
        }
    }

    func testNonStreamedCompletionParses() throws {
        let body = OpenAIFixtures.json([
            "choices": [[
                "index": 0,
                "finish_reason": "tool_calls",
                "message": [
                    "role": "assistant",
                    "content": NSNull(),
                    "reasoning_content": "plan",
                    "tool_calls": [["id": "c1", "type": "function", "function": ["name": "get_page_text", "arguments": "{}"]]]
                ]
            ]]
        ])
        let result = try OpenAIChatAccumulator.parseCompletion(body)
        XCTAssertEqual(result.content, "")
        XCTAssertEqual(result.reasoning, "plan")
        XCTAssertEqual(result.toolCalls.first?.name, "get_page_text")
        XCTAssertThrowsError(try OpenAIChatAccumulator.parseCompletion(Data("{\"id\":1}".utf8)))
        XCTAssertThrowsError(try OpenAIChatAccumulator.parseCompletion(Data("<html>".utf8)))
    }

    // MARK: - Client stream consumption

    func testClientStreamsAcrossRandomChunkBoundaries() async throws {
        for _ in 0..<20 {
            let transport = FakeOpenAITransport { _ in
                .init(headers: ["Content-Type": "text/event-stream"], body: OpenAIFixtures.answerStream("Ahoj světe 👋", reasoning: "r"))
            }
            transport.maxChunk = 4
            let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
            let result = try await client.chat(body: ["model": "m", "messages": []])
            XCTAssertEqual(result.content, "Ahoj světe 👋")
            XCTAssertEqual(result.reasoning, "r")
            XCTAssertEqual(result.usage?.totalTokens, 15)
        }
    }

    func testClientAssemblesStreamedToolCall() async throws {
        let transport = FakeOpenAITransport { _ in
            .init(headers: ["Content-Type": "text/event-stream"], body: OpenAIFixtures.toolCallStream(name: "fill", arguments: "{\"selector\":\"#email\",\"value\":\"a@b.cz\"}"))
        }
        let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
        let result = try await client.chat(body: ["model": "m", "messages": []])
        XCTAssertEqual(result.finishReason, "tool_calls")
        XCTAssertEqual(result.toolCalls.first?.parsedArguments?["value"] as? String, "a@b.cz")
        XCTAssertEqual(result.reasoning, "I should look at the page.")
    }

    func testTruncatedStreamIsAnError() async throws {
        let truncated = OpenAIFixtures.sse([OpenAIFixtures.chunk(["content": "Hal"])], done: false)
        let transport = FakeOpenAITransport { _ in .init(headers: ["Content-Type": "text/event-stream"], body: truncated) }
        let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
        do {
            _ = try await client.chat(body: [:])
            XCTFail("expected truncation error")
        } catch {
            XCTAssertEqual(error as? OpenAIEndpointError, .streamTruncated)
        }
    }

    func testStreamWithFinishReasonButNoDoneIsAccepted() async throws {
        let body = OpenAIFixtures.sse([OpenAIFixtures.chunk(["content": "ok"], finish: "stop")], done: false)
        let transport = FakeOpenAITransport { _ in .init(headers: ["Content-Type": "text/event-stream"], body: body) }
        let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
        let result = try await client.chat(body: [:])
        XCTAssertEqual(result.content, "ok")
    }

    func testServerThatIgnoresStreamFlagStillWorks() async throws {
        let body = OpenAIFixtures.json(["choices": [["index": 0, "message": ["content": "plain"], "finish_reason": "stop"]]])
        let transport = FakeOpenAITransport { _ in .init(body: body) }
        let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
        let result = try await client.chat(body: [:])
        XCTAssertEqual(result.content, "plain")
    }

    func testCancellationStopsAHangingStream() async throws {
        let body = OpenAIFixtures.sse([OpenAIFixtures.chunk(["content": "partial"])], done: false)
        let transport = FakeOpenAITransport { _ in .init(headers: ["Content-Type": "text/event-stream"], body: body, hang: true) }
        let client = OpenAIEndpointClient(baseURL: try .normalize("http://h:1/v1"), apiKey: nil, transport: transport)
        let task = Task { try await client.chat(body: [:]) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? OpenAIEndpointError) == .cancelled, "\(error)")
        }
    }
}
