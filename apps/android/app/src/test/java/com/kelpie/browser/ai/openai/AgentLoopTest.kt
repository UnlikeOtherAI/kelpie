package com.kelpie.browser.ai.openai

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    /** Replays [results] in order; when [respond] is set it decides per request instead. */
    private class ScriptedChat(
        vararg results: ChatResult,
        val respond: ((JsonArray?) -> ChatResult)? = null,
    ) : ChatTurn {
        private val queue = ArrayDeque(results.toList())
        val transcripts = mutableListOf<List<JsonObject>>()
        val toolSets = mutableListOf<JsonArray?>()

        override suspend fun complete(
            messages: List<JsonObject>,
            tools: JsonArray?,
        ): ChatResult {
            transcripts += messages.toList()
            toolSets += tools
            return respond?.invoke(tools) ?: queue.removeFirst()
        }
    }

    private fun toolTurn(vararg calls: AssembledToolCall) = ChatResult("", "secret reasoning", calls.toList(), "tool_calls", null)

    private fun answer(text: String) = ChatResult(text, "", emptyList(), "stop", mapOf("prompt_tokens" to 10, "completion_tokens" to 4))

    private fun loop(
        chat: ChatTurn,
        dispatcher: ToolDispatcher = RecordingDispatcher(),
        allowActions: Boolean = false,
        maxSteps: Int = AgentLoop.DEFAULT_MAX_STEPS,
        progress: AgentProgress = AgentProgress(),
    ) = AgentLoop(chat, dispatcher, allowActions, maxSteps, progress, actionSettleMs = 0)

    private fun toolNames(tools: JsonArray?): List<String?> = tools.orEmpty().map { OpenAIJson.string(((it as JsonObject)["function"] as JsonObject)["name"]) }

    private fun toolResult(message: JsonObject): JsonObject = OpenAIJson.parseObjectOrNull(OpenAIJson.string(message["content"])!!)!!

    @Test
    fun dispatchesToolsAndReturnsFinalAnswer() {
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "get_current_url", "{}")), answer("It is example.com"))
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { loop(chat, dispatcher).run("What page is this?") }
        assertEquals("It is example.com", outcome.text)
        assertTrue(outcome.completed)
        assertEquals(AgentLoop.STOP_ANSWERED, outcome.stopReason)
        assertEquals(2, outcome.rounds)
        assertEquals(14, outcome.promptTokens + outcome.completionTokens)
        assertEquals(listOf("get-current-url"), dispatcher.calls.map { it.first })
        assertTrue(outcome.steps.single().ok)
        assertEquals("secret reasoning", outcome.reasoning)
        val second = chat.transcripts[1]
        val system = OpenAIJson.string(second[0]["content"])!!
        assertTrue(system.contains("untrusted"))
        assertTrue(system.contains("Start by calling update_task_list"))
        assertTrue(system.contains("Every tool result reports stepsRemaining"))
        assertEquals("c1", OpenAIJson.string(second.last()["tool_call_id"]))
        val result = toolResult(second.last())
        assertEquals(true, OpenAIJson.boolean(result["ok"]))
        assertEquals(AgentLoop.DEFAULT_MAX_STEPS - 1, OpenAIJson.int(result["stepsRemaining"]))
        assertFalse("reasoning must never be fed back", second.any { OpenAIJson.encode(it).contains("secret reasoning") })
        assertEquals(AgentTaskList.TOOL_NAME, toolNames(chat.toolSets[0]).first())
    }

    @Test
    fun stepsRemainingCountsDownAndFloorsAtZero() {
        val chat =
            ScriptedChat(
                toolTurn(AssembledToolCall(0, "a", "get_current_url", "{}"), AssembledToolCall(1, "b", "get_page_text", "{}")),
                answer("done"),
            )
        runBlocking { loop(chat, maxSteps = 2).run("x") }
        val remaining =
            chat.transcripts[1]
                .filter { OpenAIJson.string(it["role"]) == "tool" }
                .map { OpenAIJson.int(toolResult(it)["stepsRemaining"]) }
        assertEquals(listOf(1, 0), remaining)
    }

    @Test
    fun dropsTabIdWindowIdAndUnknownArguments() {
        val args = """{"selector":"#q","tabId":"evil","windowId":"w","script":"alert(1)","timeout":"99999"}"""
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "wait_for_element", args)), answer("done"))
        val dispatcher = RecordingDispatcher()
        runBlocking { loop(chat, dispatcher).run("x") }
        val sent = dispatcher.calls.single().second
        assertEquals(setOf("selector", "timeout"), sent.keys)
        assertEquals(AgentTools.MAX_WAIT_TIMEOUT_MS, sent["timeout"])
    }

    @Test
    fun actionToolsOnlyOfferedWhenAllowed() {
        val readOnly = toolNames(JsonArray(listOf(AgentTaskList.definition()) + AgentTools.definitions(false)))
        assertFalse("click" in readOnly)
        assertTrue("get_page_text" in readOnly)
        assertTrue(AgentTaskList.TOOL_NAME in readOnly)
        val withActions = toolNames(AgentTools.definitions(true))
        assertTrue(listOf("click", "fill", "select_option", "check", "uncheck").all { it in withActions })
        listOf("navigate", "evaluate", "screenshot", "get_cookies", "new_tab").forEach { assertFalse(it in withActions) }

        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c1", "click", """{"selector":"#buy"}""")), answer("no"))
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { loop(chat, dispatcher).run("x") }
        assertTrue(dispatcher.calls.isEmpty())
        assertFalse(outcome.steps.single().ok)
        assertTrue(
            outcome.steps
                .single()
                .preview
                .contains("Page actions are not enabled"),
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
        val outcome = runBlocking { loop(chat, dispatcher).run("x") }
        assertEquals("gave up", outcome.text)
        assertTrue(dispatcher.calls.isEmpty())
        assertTrue(outcome.steps[0].preview.contains("not valid JSON"))
        assertTrue(outcome.steps[1].preview.contains("text is required"))
        assertEquals("call_1", OpenAIJson.string(chat.transcripts[1].last()["tool_call_id"]))
    }

    @Test
    fun toolResultsAreTruncated() {
        val big = mapOf<String, Any?>("success" to true, "content" to "z".repeat(20_000))
        val chat = ScriptedChat(toolTurn(AssembledToolCall(0, "c", "get_page_text", "{}")), answer("ok"))
        runBlocking { loop(chat, RecordingDispatcher { big }).run("x") }
        val content = OpenAIJson.string(chat.transcripts[1].last()["content"])!!
        assertTrue(content.startsWith("{\"ok\":true"))
        assertTrue(content.contains("… [truncated, "))
        assertTrue(content.length < AgentLoop.TOOL_RESULT_CHARS + 60)
    }

    /** Mirrors Swift `testStepBudgetEndsWithFinalReportWithoutTools`. */
    @Test
    fun stepBudgetEndsWithFinalReportWithoutTools() {
        val chat =
            ScriptedChat(
                respond = { tools ->
                    if (tools == null) {
                        answer("I read the page twice but did not finish.")
                    } else {
                        toolTurn(AssembledToolCall(0, "c", "get_page_text", "{}"))
                    }
                },
            )
        val outcome = runBlocking { loop(chat, maxSteps = 3).run("loop") }
        assertFalse(outcome.completed)
        assertEquals(AgentLoop.STOP_STEP_LIMIT, outcome.stopReason)
        assertEquals(3, outcome.steps.size)
        assertEquals("I read the page twice but did not finish.", outcome.text)
        assertNull("the final report request offers no tools", chat.toolSets.last())
        val finalMessages = chat.transcripts.last()
        assertTrue(OpenAIJson.string(finalMessages.last()["content"])!!.contains("step budget"))
        assertFalse("no dangling tool_calls turn", finalMessages[finalMessages.size - 2].containsKey("tool_calls"))
    }

    /** Mirrors Swift `testTaskListIsFreeAndOpenTasksEarnOneMoreTurn`. */
    @Test
    fun taskListIsFreeAndOpenTasksEarnOneMoreTurn() {
        val plan = """{"tasks":[{"task":"Read the page","done":false},{"task":"Report the title","done":false}]}"""
        val finished = """{"tasks":[{"task":"Read the page","done":true},{"task":"Report the title","done":true}]}"""
        val chat =
            ScriptedChat(
                toolTurn(AssembledToolCall(0, "t1", AgentTaskList.TOOL_NAME, plan)),
                toolTurn(AssembledToolCall(0, "c1", "get_page_text", "{}")),
                answer("Premature answer."),
                toolTurn(AssembledToolCall(0, "t2", AgentTaskList.TOOL_NAME, finished)),
                answer("The title is Riverside Book Club."),
            )
        val dispatcher = RecordingDispatcher()
        val outcome = runBlocking { loop(chat, dispatcher, maxSteps = 1).run("What is the title?") }
        assertTrue(outcome.completed)
        assertEquals("The title is Riverside Book Club.", outcome.text)
        assertEquals("task-list updates do not use browser steps", 1, outcome.steps.size)
        assertEquals(listOf("get-page-text"), dispatcher.calls.map { it.first })
        assertEquals(listOf(true, true), outcome.tasks.map { it.done })
        assertTrue(OpenAIJson.encode(JsonArray(chat.transcripts[3])).contains("unfinished tasks"))
        val taskResult = toolResult(chat.transcripts[1].last())
        assertEquals(true, OpenAIJson.boolean(taskResult["ok"]))
        assertEquals(2, (taskResult["remaining"] as JsonArray).size)
    }

    @Test
    fun openTasksEarnOnlyOneReminder() {
        val plan = """{"tasks":[{"task":"Never done","done":false}]}"""
        val chat =
            ScriptedChat(
                toolTurn(AssembledToolCall(0, "t1", AgentTaskList.TOOL_NAME, plan)),
                answer("First stop."),
                answer("Second stop."),
            )
        val outcome = runBlocking { loop(chat).run("x") }
        assertEquals("Second stop.", outcome.text)
        assertTrue(outcome.completed)
        assertEquals(listOf(false), outcome.tasks.map { it.done })
    }

    @Test
    fun taskListIsCappedAndValidated() {
        val tasks = (1..30).joinToString(",") { """{"task":"${"t".repeat(300)}$it","done":false}""" }
        val list = AgentTaskList()
        list.apply(AssembledToolCall(0, "t", AgentTaskList.TOOL_NAME, """{"tasks":[$tasks,{"task":"  "}]}"""))
        assertEquals(AgentTaskList.MAX_ITEMS, list.items.size)
        assertTrue(list.items.all { it.task.length == AgentTaskList.MAX_TASK_CHARS })
        val bad = list.apply(AssembledToolCall(0, "t", AgentTaskList.TOOL_NAME, "{}"))
        assertTrue(bad.contains("\"ok\":false"))
    }

    @Test
    fun maxStepsIsCappedAt40() {
        val chat =
            ScriptedChat(
                respond = { tools -> if (tools == null) answer("report") else toolTurn(AssembledToolCall(0, "c", "get_current_url", "{}")) },
            )
        val outcome = runBlocking { loop(chat, maxSteps = 100).run("x") }
        assertEquals(AgentLoop.MAX_STEPS, outcome.steps.size)
        assertEquals(AgentLoop.STOP_STEP_LIMIT, outcome.stopReason)
    }

    @Test
    fun failedFinalReportIsAgentStepLimit() {
        val chat =
            ScriptedChat(
                respond = { tools ->
                    if (tools == null) throw OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "gone")
                    toolTurn(AssembledToolCall(0, "c", "get_current_url", "{}"))
                },
            )
        try {
            runBlocking { loop(chat, maxSteps = 2).run("x") }
            fail("expected step limit")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.AGENT_STEP_LIMIT, e.code)
        }
    }

    @Test
    fun emptyAnswerIsAnError() {
        val chat = ScriptedChat(ChatResult("  ", "", emptyList(), "length", null))
        try {
            runBlocking { loop(chat).run("x") }
            fail("expected error")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_ERROR, e.code)
            assertTrue(e.message.contains("Increase maxTokens"))
        }
    }

    @Test
    fun progressKeepsStepsWhenTheRunFails() {
        val chat =
            ScriptedChat(
                respond = { tools ->
                    if (tools != null && progressCalls++ == 0) {
                        toolTurn(AssembledToolCall(0, "c", "get_current_url", "{}"))
                    } else {
                        throw OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "gone")
                    }
                },
            )
        val progress = AgentProgress()
        try {
            runBlocking { loop(chat, progress = progress).run("x") }
            fail("expected failure")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_UNREACHABLE, e.code)
        }
        assertEquals(1, progress.steps.size)
        assertEquals("secret reasoning", progress.reasoning)
    }

    private var progressCalls = 0
}
