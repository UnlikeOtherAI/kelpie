package com.kelpie.browser.automation

import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ScriptTargetCallbackFlowTest : ScriptPublicFixture() {
    @Test
    fun realWebViewClassificationPrecedesFailingCallbackGuardAndPreflightDoesNotStart() =
        runBlocking {
            MockWebServer().use { server ->
                server.start()
                ScriptHttpFixture().use { client ->
                    pair(client)
                    load(client, server)
                    val context = HandlerContext()
                    context.webView = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                    val state = ScriptTargetClassification()
                    val guards = AtomicInteger()
                    var consumed = false
                    try {
                        context.evaluateAutomationJSON(
                            "({ok:true,sensitive:false})",
                            { guards.incrementAndGet() == 1 },
                            state::started,
                        ) { result ->
                            consumed = true
                            assertEquals(false, result["sensitive"])
                            state.received(result["sensitive"] as? Boolean)
                        }
                        throw AssertionError("Expected callback guard refusal")
                    } catch (_: IllegalStateException) {
                        assertTrue(consumed)
                        assertEquals(2, guards.get())
                        assertFalse("Known non-sensitive result must preserve ordinary partials", state.unknown())
                    }
                    // An initial click resolve/recheck has no dispatch flag, but a
                    // missing result still cannot certify capture as non-sensitive.
                    val lostClick = ScriptTargetClassification()
                    val clickGuards = AtomicInteger()
                    try {
                        context.evaluateAutomationJSON(
                            "({ok:false,error:'TARGET_EVALUATION_FAILED'})",
                            { clickGuards.incrementAndGet() == 1 },
                            lostClick::started,
                        ) { result -> lostClick.received(result["sensitive"] as? Boolean) }
                        throw AssertionError("Expected callback guard refusal")
                    } catch (_: IllegalStateException) {
                        assertTrue("Lost click classification must protect capture", lostClick.unknown())
                    }
                    val refused = ScriptTargetClassification()
                    try {
                        context.evaluateAutomationJSON("({ok:true,sensitive:false})", { false }, refused::started)
                        throw AssertionError("Expected pre-evaluation refusal")
                    } catch (_: IllegalStateException) {
                        assertFalse("No evaluation occurred", refused.unknown())
                    }
                }
            }
        }
}
