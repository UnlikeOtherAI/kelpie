package com.kelpie.browser.ai.openai

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AgentLoopTest {
    private class RecordingDispatcher(
        val result: (String) -> Map<String, Any?> = { mapOf("success" to true, "url" to "https://example.com") },
    ) : ToolDispatcher {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()

        override suspend fun dispatch(
            method: String,
            args: Map<String, Any?>,
        ): Map<String, Any?> {
            calls += method to args
            return result(method)
        }
    }

    private class ScriptedChat(
        vararg results: ChatResult,
    ) : ChatTurn {
        private val queue = ArrayDeque(results.toList())
        val transcripts = mutableListOf<List<JsonObject>>()
        val toolSets = mutableListOf<JsonArray>()

        override suspend fun complete(
            messages: List<JsonObject>,
            tools: JsonArray,
        ): ChatResult {
            transcripts += messages.toList()
            toolSets += tools
            return queue.removeFirst()
        }
    }

    private fun toolTurn(vararg calls: AssembledToolCall) = ChatResult("", "secret reasoning", calls.toList(), "tool_calls", null)

    private fun answer(text: String) = ChatResult(text, "", emptyList(), "stop", mapOf("completion_tokens" to 4))

    private val user = listOf(JsonObject(mapOf("role" to JsonPrimitive("user"), "content" to JsonPrimitive("What page is this?"))))

    @Test
    fun dispatchesToolsAndReturnsFinalAnswer() {
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "get_current_url", "{}")), answer("It is example.com"))
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { AgentLoop(chat, dispatcher, allowActions = false).run(user) }
        assertEquals("It is example.com", outcome.text)
        assertEquals("stop", outcome.finishReason)
        assertEquals(listOf("get-current-url"), dispatcher.calls.map { it.first })
        assertEquals(1, outcome.steps.size)
        assertTrue(outcome.steps[0].ok)
        assertEquals("secret reasoning", outcome.reasoning)
        val second = chat.transcripts[1]
        assertEquals("system", OpenAIJson.string(second[0]["role"]))
        assertTrue(OpenAIJson.string(second[0]["content"])!!.contains("untrusted"))
        assertEquals("tool", OpenAIJson.string(second.last()["role"]))
        assertEquals("c1", OpenAIJson.string(second.last()["tool_call_id"]))
        assertFalse("reasoning must never be fed back", second.any { OpenAIJson.encode(it).contains("secret reasoning") })
    }

    @Test
    fun dropsTabIdWindowIdAndUnknownArguments() {
        val args = """{"selector":"#q","tabId":"evil","windowId":"w","script":"alert(1)","timeout":"99999"}"""
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "wait_for_element", args)), answer("done"))
        val dispatcher = RecordingDispatcher()
        runBlocking { AgentLoop(chat, dispatcher, allowActions = false).run(user) }
        val sent = dispatcher.calls.single().second
        assertEquals(setOf("selector", "timeout"), sent.keys)
        assertEquals(AgentTools.MAX_WAIT_TIMEOUT_MS, sent["timeout"])
    }

    @Test
    fun actionToolsOnlyOfferedWhenAllowed() {
        val readOnly = AgentTools.definitions(false).map { OpenAIJson.string((it as JsonObject)["function"]!!.let { f -> (f as JsonObject)["name"] }) }
        assertFalse("click" in readOnly)
        assertTrue("get_page_text" in readOnly)
        val withActions = AgentTools.definitions(true).map { OpenAIJson.string(((it as JsonObject)["function"] as JsonObject)["name"]) }
        assertTrue(listOf("click", "fill", "select_option", "check", "uncheck").all { it in withActions })
        listOf("navigate", "evaluate", "screenshot", "get_cookies", "new_tab").forEach { assertFalse(it in withActions) }

        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "click", """{"selector":"#buy"}""")), answer("no"))
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { AgentLoop(chat, dispatcher, allowActions = false).run(user) }
        assertTrue(dispatcher.calls.isEmpty())
        assertFalse(outcome.steps.single().ok)
        assertTrue(
            outcome.steps
                .single()
                .preview
                .contains("ACTIONS_NOT_ALLOWED"),
        )
    }

    @Test
    fun malformedArgumentsAreReportedAndLoopContinues() {
        val chat =
            ScriptedChat(
                toolTurn(AssembledToolCall(0, null, "find_element", "{\"text\": ")),
                toolTurn(AssembledToolCall(0, null, "find_element", "{}")),
                answer("gave up"),
            )
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { AgentLoop(chat, dispatcher, allowActions = false).run(user) }
        assertEquals("gave up", outcome.text)
        assertTrue(dispatcher.calls.isEmpty())
        assertTrue(outcome.steps[0].preview.contains("MALFORMED_ARGUMENTS"))
        assertTrue(outcome.steps[1].preview.contains("MISSING_PARAM"))
        val toolMessage = chat.transcripts[1].last()
        assertEquals("call_1", OpenAIJson.string(toolMessage["tool_call_id"]))
    }

    @Test
    fun toolResultsAreTruncated() {
        val big = mapOf<String, Any?>("success" to true, "content" to "z".repeat(20_000))
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c", "get_page_text", "{}")), answer("ok"))
        runBlocking { AgentLoop(chat, RecordingDispatcher { big }, allowActions = false).run(user) }
        val content = OpenAIJson.string(chat.transcripts[1].last()["content"])!!
        assertEquals(AgentLoop.TOOL_RESULT_CHARS, content.length)
    }

    @Test
    fun stepLimitFailsWithAgentStepLimit() {
        val turns = Array(10) { toolTurn(AssembledToolCall(0, "c$it", "get_current_url", "{}")) }
        try {
            runBlocking { AgentLoop(ScriptedChat(*turns), RecordingDispatcher(), allowActions = false, maxSteps = 3).run(user) }
            fail("expected step limit")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.AGENT_STEP_LIMIT, e.code)
            assertEquals(3, (e.diagnostics?.get("steps") as List<*>).size)
        }
    }

    @Test
    fun maxStepsIsCappedAt25() {
        val turns = Array(30) { toolTurn(AssembledToolCall(0, "c$it", "get_current_url", "{}")) }
        try {
            runBlocking { AgentLoop(ScriptedChat(*turns), RecordingDispatcher(), allowActions = false, maxSteps = 100).run(user) }
            fail("expected step limit")
        } catch (e: OpenAIException) {
            assertEquals(AgentLoop.MAX_STEPS, (e.diagnostics?.get("steps") as List<*>).size)
        }
    }
}
