package com.kelpie.browser.ai.openai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import kotlin.random.Random

class StreamParsingTest {
    private fun parseEvents(
        bytes: ByteArray,
        chunker: (Int) -> Int,
    ): Pair<List<SSEEvent>, List<String>> {
        val events = mutableListOf<SSEEvent>()
        val comments = mutableListOf<String>()
        val parser = SSEParser(onEvent = { events += it }, onComment = { comments += it })
        var offset = 0
        while (offset < bytes.size) {
            val size = chunker(offset).coerceIn(1, bytes.size - offset)
            parser.feed(bytes.copyOfRange(offset, offset + size))
            offset += size
        }
        parser.finish()
        return events to comments
    }

    @Test
    fun handlesAllLineEndingsCommentsAndFields() {
        val text = ": keep-alive\r\nevent: message\r\nid: 7\r\ndata: one\r\n\r\ndata: two\rdata: lines\r\rdata:three\n\n"
        val (events, comments) = parseEvents(text.toByteArray()) { 1000 }
        assertEquals(listOf("keep-alive"), comments)
        assertEquals(3, events.size)
        assertEquals(SSEEvent("message", "one", "7"), events[0])
        assertEquals("two\nlines", events[1].data)
        assertNull(events[1].event)
        assertEquals("three", events[2].data)
    }

    @Test
    fun byteByByteAndRandomChunksMatchWholeParse() {
        val text = ": ping\n\ndata: héllo 🦭 wörld\n\ndata: {\"a\":\"日本語\"}\r\n\r\ndata: [DONE]\n\n"
        val bytes = text.toByteArray(Charsets.UTF_8)
        val whole = parseEvents(bytes) { bytes.size }.first
        assertEquals(listOf("héllo 🦭 wörld", "{\"a\":\"日本語\"}", "[DONE]"), whole.map { it.data })
        assertEquals(whole, parseEvents(bytes) { 1 }.first)
        repeat(50) { seed ->
            val random = Random(seed)
            assertEquals(whole, parseEvents(bytes) { 1 + random.nextInt(9) }.first)
        }
    }

    @Test
    fun crlfSplitAcrossChunksIsOneLineEnding() {
        val bytes = "data: a\r\n\r\ndata: b\r\n\r\n".toByteArray()
        // split exactly between \r and \n
        val events = parseEvents(bytes) { offset -> if (offset == 0) 8 else 1 }.first
        assertEquals(listOf("a", "b"), events.map { it.data })
    }

    @Test
    fun finishFlushesEventWithoutTrailingBlankLine() {
        val events = parseEvents("data: tail".toByteArray()) { 100 }.first
        assertEquals(listOf("tail"), events.map { it.data })
    }

    private fun accumulate(
        stream: String,
        seed: Int = 1,
    ): ChatResult {
        val accumulator = ChatAccumulator(apiKey = "sk-secret")
        val parser = SSEParser(onEvent = { if (!accumulator.sawDone) accumulator.consume(it.data) })
        val bytes = stream.toByteArray(Charsets.UTF_8)
        val random = Random(seed)
        var offset = 0
        while (offset < bytes.size) {
            val size = (1 + random.nextInt(5)).coerceAtMost(bytes.size - offset)
            parser.feed(bytes.copyOfRange(offset, offset + size))
            offset += size
        }
        parser.finish()
        return accumulator.finish()
    }

    @Test
    fun separatesContentFromReasoningAndIgnoresRoleOnlyDeltas() {
        val stream =
            Fixtures.sse(
                """{"choices":[{"index":0,"delta":{"role":"assistant"}}]}""",
                """{"choices":[{"index":0,"delta":{"reasoning_content":"think "}}]}""",
                """{"choices":[{"index":0,"delta":{"reasoning":"more"}}]}""",
                Fixtures.contentFrame("Hel"),
                Fixtures.contentFrame("lo ✓"),
                """{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}""",
                """{"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":3}}""",
            )
        repeat(20) { seed ->
            val result = accumulate(stream, seed)
            assertEquals("Hello ✓", result.content)
            assertEquals("think more", result.reasoning)
            assertEquals("stop", result.finishReason)
            assertEquals(3, result.usage?.get("completion_tokens"))
            assertTrue(result.toolCalls.isEmpty())
        }
    }

    @Test
    fun assemblesFragmentedToolCallsByIndex() {
        val stream =
            Fixtures.sse(
                """{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"fi","arguments":""}}]}}]}""",
                """{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"ll","arguments":"{\"sel"}}]}}]}""",
                """{"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","function":{"name":"click","arguments":"{\"selector\":"}}]}}]}""",
                """{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"ignored","function":{"arguments":"ector\":\"#q\",\"value\":\"ünï\"}"}}]}}]}""",
                """{"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"#go\"}"}}]}}]}""",
                """{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}""",
            )
        repeat(20) { seed ->
            val calls = accumulate(stream, seed).toolCalls
            assertEquals(2, calls.size)
            assertEquals("call_a", calls[0].id)
            assertEquals("fill", calls[0].name)
            assertEquals("#q", OpenAIJson.string(calls[0].parsedArguments()!!["selector"]))
            assertEquals("ünï", OpenAIJson.string(calls[0].parsedArguments()!!["value"]))
            assertEquals("click", calls[1].name)
            assertEquals("#go", OpenAIJson.string(calls[1].parsedArguments()!!["selector"]))
        }
    }

    @Test
    fun repeatedFullToolNameIsNotDoubled() {
        val stream =
            Fixtures.sse(
                """{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c","function":{"name":"click","arguments":"{"}}]}}]}""",
                """{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"click","arguments":"}"}}]}}]}""",
            )
        assertEquals("click", accumulate(stream).toolCalls.single().name)
    }

    @Test
    fun malformedToolArgumentsParseToNull() {
        val call = AssembledToolCall(0, "c", "click", "{\"selector\": ")
        assertNull(call.parsedArguments())
        assertEquals(0, AssembledToolCall(0, "c", "get_current_url", "").parsedArguments()!!.size)
    }

    @Test
    fun streamWithoutDoneButWithFinishReasonIsAccepted() {
        val stream = "data: ${Fixtures.contentFrame("ok")}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n\n"
        assertEquals("length", accumulate(stream).finishReason)
    }

    @Test
    fun streamWithoutDoneOrFinishReasonIsTruncated() {
        val stream = "data: ${Fixtures.contentFrame("partial")}\n\n"
        try {
            accumulate(stream)
            fail("expected truncation")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_STREAM_TRUNCATED, e.code)
        }
    }

    @Test
    fun errorFramesBecomeEndpointErrorWithRedactedKey() {
        val accumulator = ChatAccumulator(apiKey = "sk-secret")
        try {
            accumulator.consume("""{"error":{"message":"bad key sk-secret","type":"invalid_request_error"}}""")
            fail("expected error")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_ERROR, e.code)
            assertFalse(e.message.contains("sk-secret"))
            assertTrue(e.message.contains("[redacted]"))
        }
    }

    @Test
    fun nonStreamingResponseUsesSameModel() {
        val body =
            """{"choices":[{"index":0,"message":{"role":"assistant","content":"Hi","reasoning_content":"hmm",""" +
                """"tool_calls":[{"id":"c1","type":"function","function":{"name":"click","arguments":"{\"selector\":\"#a\"}"}}]},""" +
                """"finish_reason":"tool_calls"}],"usage":{"completion_tokens":2}}"""
        val result = ChatAccumulator().consumeCompleteResponse(body)
        assertEquals("Hi", result.content)
        assertEquals("hmm", result.reasoning)
        assertEquals("click", result.toolCalls.single().name)
        assertEquals("tool_calls", result.finishReason)
    }

    @Test
    fun serverErrorTextIsRedactedAndCapped() {
        val raw = "{\"error\":{\"message\":\"" + "x".repeat(500) + " sk-secret\"}}"
        val text = ServerErrorText.sanitize(raw, "sk-secret")
        assertTrue(text.length <= ServerErrorText.MAX_LENGTH)
        assertFalse(text.contains("sk-secret"))
        assertEquals("plain [redacted] text", ServerErrorText.sanitize("plain sk-secret\n text", "sk-secret"))
    }
}
