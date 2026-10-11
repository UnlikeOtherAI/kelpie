package com.kelpie.browser.ai

import com.kelpie.browser.ai.openai.OpenAIException
import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.llm.PageTextSnapshot
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AIPageContextTest {
    @Test
    fun completeConversationSurvivesPromptComposition() {
        val messages = (0 until 24).map { mapOf("role" to if (it % 2 == 0) "user" else "assistant", "content" to "turn-$it") }
        val body = mapOf("messages" to messages, "prompt" to "Recall the first turn")
        assertEquals(24, AIConversation.messages(body).size)
        val prompt = AIConversation.prompt(body)
        assertTrue(prompt.contains("turn-0"))
        assertTrue(prompt.contains("turn-23"))
        assertTrue(prompt.contains("Recall the first turn"))
    }

    @Test
    fun malformedHistoryFailsInsteadOfDroppingTurns() {
        assertFailure("INVALID_PARAM") { AIConversation.messages(mapOf("messages" to listOf(mapOf("role" to "tool", "content" to "hidden")))) }
        assertFailure("INVALID_PARAM") { AIConversation.messages(mapOf("messages" to listOf(mapOf("role" to "user", "content" to 3)))) }
    }

    @Test
    fun pageEvidenceKeepsLabelsBeyondBodyLimit() {
        val evidence =
            AIConversation.pageEvidence(
                mapOf("content" to "x".repeat(20000), "accessibleLabels" to listOf("UnlikeOtherAI logo"), "url" to "https://example.test"),
            )
        assertTrue(evidence.contains("UnlikeOtherAI logo"))
        assertTrue(evidence.contains("example.test"))
        assertTrue(evidence.length < 13000)
    }

    @Test
    fun failedReadStopsInferenceAndRetainsError() =
        runBlocking {
            try {
                AIPageContext.evidence(mapOf("ok" to false, "error" to mapOf("code" to "TAB_NOT_FOUND", "message" to "Tab closed")))
                fail("A failed read must never be empty page context")
            } catch (error: OpenAIException) {
                assertEquals("TAB_NOT_FOUND", error.code)
            }
        }

    @Test
    fun commonEvidenceIncludesGroundingButOmitsFormValues() {
        val evidence = AIPageContext.evidence(mapOf("ok" to true, "value" to mapOf(
            "title" to "Page", "url" to "https://example.test", "text" to "Public text", "truncated" to true,
            "elements" to listOf(mapOf("name" to "Logo", "value" to "secret-input")),
        )))
        assertTrue(evidence.contains("Logo"))
        assertTrue(evidence.contains("truncated"))
        assertFalse(evidence.contains("secret-input"))
        assertFailure("EVAL_ERROR") { AIPageContext.evidence(mapOf("ok" to true, "value" to emptyMap<String, Any>())) }
    }

    @Test
    fun snapshotDecodeDistinguishesEmptyPageFromFailedRead() {
        val empty = mapOf("title" to "", "url" to "about:blank", "content" to "", "accessibleLabels" to emptyList<String>())
        val raw = OpenAIJson.encode(OpenAIJson.fromAny(OpenAIJson.encode(OpenAIJson.fromAny(empty))))
        assertEquals("", PageTextSnapshot.decode(raw)["content"])
        assertFailure("EVAL_ERROR") { PageTextSnapshot.decode("null") }
        assertFailure("EVAL_ERROR") { PageTextSnapshot.decode("\"{}\"") }
    }

    @Test
    fun snapshotScriptIncludesAccessibleLogoNamesAndIgnoresHiddenNames() {
        val script = PageTextSnapshot.script("body")
        assertTrue(script.contains("img[alt]"))
        assertTrue(script.contains("aria-labelledby"))
        assertTrue(script.contains("querySelector('title')"))
        assertTrue(script.contains("aria-hidden"))
        assertFalse(script.contains("fetch("))
    }

    private fun assertFailure(
        code: String,
        block: () -> Unit,
    ) {
        try {
            block()
            fail("Expected $code")
        } catch (error: OpenAIException) {
            assertEquals(code, error.code)
        }
    }
}
