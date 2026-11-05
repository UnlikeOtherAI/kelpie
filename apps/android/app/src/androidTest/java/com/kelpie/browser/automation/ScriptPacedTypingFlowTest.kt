package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScriptPacedTypingFlowTest : ScriptPublicFixture() {
    private fun runCase(
        mode: String,
        action: String,
        text: String,
        capture: Boolean,
        verify: (ScriptHttpFixture, JSONObject, JSONObject) -> Unit,
    ) {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val title = if (mode == "sensitive") "Paced fixture AB" else "Paced fixture"
                val onInput =
                    when (mode) {
                        "blur" -> "if(window.events.length===1)this.blur()"
                        "sensitive" -> "if(this.value.length===1)this.type='password'"
                        else -> ""
                    }
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html; charset=utf-8").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>$title</title>
                        <label>Name<input value="old" onfocus="window.focusCount=(window.focusCount||0)+1" oninput="window.events.push({data:event.data,value:this.value,time:performance.now()});document.title=this.value;$onInput"></label>
                        <script>window.events=[];window.focusCount=0;</script>""",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/paced").toString())).getBoolean("success"))
                val deadline = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != title && System.nanoTime() < deadline) Thread.sleep(20)
                assertEquals(title, client.core("tab.title", tab).getString("value"))
                val edit =
                    client
                        .action(action)
                        .put("target", JSONObject().put("label", "Name"))
                        .put("text", text)
                        .put("typingDelayMs", 100)
                val workflow =
                    if (mode == "sensitive") {
                        client.script(tab, client.action("output").put("name", "before").put("source", "title"), edit)
                    } else if (mode == "fill") {
                        client.script(tab, edit, client.action("output").put("name", "after").put("source", "title"))
                    } else {
                        client.script(tab, edit)
                    }
                if (capture) workflow.put("capture", JSONObject().put("formats", JSONArray(listOf("gif", "video", "screenshots"))).put("fps", 5).put("maxWidth", 320))
                val result = playRecorded(client, workflow)
                val facts =
                    client
                        .call(
                            "evaluate",
                            JSONObject().put("expression", "({events:window.events,focusCount:window.focusCount,value:document.querySelector('input').value})"),
                        ).getJSONObject("result")
                File(evidence, "paced-$mode-result.json").writeText(result.toString(2))
                File(evidence, "paced-$mode-facts.json").writeText(facts.toString(2))
                verify(client, result, facts)
            }
        }
    }

    @Test
    fun nativePlannerUsesUnicodeScalarsAndRejectsInvalidDelay() {
        val request = JSONObject().put("action", "fill").put("text", "A\uD83C\uDF0AB").put("typingDelayMs", 100)
        val plan = JSONObject(checkNotNull(ScriptNative.typingPlan(request.toString())))
        assertTrue(plan.getBoolean("valid"))
        assertTrue(plan.getBoolean("clearFirst"))
        val scalars = plan.getJSONArray("scalars")
        assertEquals(3, scalars.length())
        assertEquals("\uD83C\uDF0A", scalars.getString(1))
        request.put("typingDelayMs", 1001)
        val invalid = JSONObject(checkNotNull(ScriptNative.typingPlan(request.toString())))
        assertFalse(invalid.getBoolean("valid"))
        assertFalse(invalid.toString().contains("A\uD83C\uDF0AB"))
    }

    @Test
    fun pacedFillClearsOnceAndTypesUnicodeScalarsWithMoviesAndScreenshots() =
        runCase("fill", "fill", "A\uD83C\uDF0AB", true) { client, result, facts ->
            assertTrue(result.getBoolean("success"))
            assertEquals("A\uD83C\uDF0AB", result.getJSONObject("outputs").getString("after"))
            val events = facts.getJSONArray("events")
            assertEquals(4, events.length())
            assertEquals("", events.getJSONObject(0).getString("value"))
            assertEquals("A", events.getJSONObject(1).getString("value"))
            assertEquals("A\uD83C\uDF0A", events.getJSONObject(2).getString("value"))
            assertEquals("A\uD83C\uDF0AB", events.getJSONObject(3).getString("value"))
            for (i in 2..3) assertTrue(events.getJSONObject(i).getDouble("time") - events.getJSONObject(i - 1).getDouble("time") >= 80)
            val artifacts = result.getJSONArray("artifacts")
            val mimes = (0 until artifacts.length()).map { artifacts.getJSONObject(it).getString("mimeType") }.toSet()
            assertTrue(mimes.containsAll(setOf("image/gif", "video/mp4", "image/png")))
            for (i in 0 until artifacts.length()) retrieve(client, result.getString("runId"), artifacts.getJSONObject(i))
        }

    @Test
    fun pacedTypeStopsWhenFocusIsStolen() =
        runCase("blur", "type", "AB", false) { _, result, facts ->
            assertFalse(result.getBoolean("success"))
            assertEquals("INPUT_UNCERTAIN", result.getJSONObject("error").getString("code"))
            assertTrue(result.getBoolean("mayHaveCompleted"))
            assertEquals(1, facts.getJSONArray("events").length())
            assertEquals("oldA", facts.getString("value"))
        }

    @Test
    fun pacedSensitiveTransitionDiscardsCaptureBeforeFurtherCharacters() =
        runCase("sensitive", "fill", "AB", true) { _, result, facts ->
            assertFalse(result.getBoolean("success"))
            assertEquals("SENSITIVE_CAPTURE_REFUSED", result.getJSONObject("error").getString("code"))
            assertEquals(0, result.getJSONArray("artifacts").length())
            assertFalse(result.getJSONObject("outputs").getString("before").contains("AB"))
            assertEquals("A", facts.getString("value"))
            assertEquals(2, facts.getJSONArray("events").length())
        }

    @Test
    fun acknowledgedFinalScalarCanNavigateWithoutInventingInputFailure() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Navigation AB</title>
                        <label>Name<input oninput="if(this.value==='AB')location.href='/paced-destination'"></label>""",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/paced-navigation").toString())).getBoolean("success"))
                val end = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != "Navigation AB" && System.nanoTime() < end) Thread.sleep(20)
                assertEquals("Navigation AB", client.core("tab.title", tab).getString("value"))
                server.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody("<!doctype html><title>Paced destination</title>"))
                val workflow =
                    client.script(
                        tab,
                        client.action("output").put("name", "before").put("source", "title"),
                        client
                            .action("type")
                            .put("target", JSONObject().put("label", "Name"))
                            .put("text", "AB")
                            .put("typingDelayMs", 100),
                    )
                val result = playRecorded(client, workflow)
                File(evidence, "paced-final-navigation-result.json").writeText(result.toString(2))
                assertTrue("Acknowledged final scalar should complete", result.getBoolean("success"))
                assertEquals(2, result.getInt("actionsExecuted"))
            }
        }
    }

    @Test
    fun abortDuringPacedTypingStopsBeforeTheNextScalar() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html; charset=utf-8").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Cancel paced</title>
                        <label>Name<input oninput="window.events.push(this.value);if(window.events.length===1)fetch('/first-input')"></label>
                        <script>window.events=[];</script>""",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/cancel-paced").toString())).getBoolean("success"))
                val deadline = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != "Cancel paced" && System.nanoTime() < deadline) Thread.sleep(20)
                assertEquals("Cancel paced", client.core("tab.title", tab).getString("value"))
                server.enqueue(MockResponse().setResponseCode(204))
                val action =
                    client
                        .action("type")
                        .put("target", JSONObject().put("label", "Name"))
                        .put("text", "AB")
                        .put("typingDelayMs", 1000)
                val workflow = client.script(tab, action).put("capture", JSONObject().put("formats", JSONArray(listOf("gif", "video", "screenshots"))).put("fps", 5).put("maxWidth", 320))
                val executor =
                    java.util.concurrent.Executors
                        .newSingleThreadExecutor()
                try {
                    val pending = executor.submit<JSONObject> { client.call("play-script", workflow) }
                    awaitRecordingUi(pending)
                    var found = false
                    val end = System.nanoTime() + 20_000_000_000L
                    while (!found && !pending.isDone && System.nanoTime() < end) {
                        val request = server.takeRequest(500, java.util.concurrent.TimeUnit.MILLISECONDS)
                        found = request?.path == "/first-input"
                    }
                    assertTrue("First scalar was not observed", found)
                    assertTrue(client.call("abort-script").getBoolean("success"))
                    val result = pending.get(30, java.util.concurrent.TimeUnit.SECONDS)
                    assertFalse(result.getBoolean("success"))
                    assertEquals("SCRIPT_ABORTED", result.getJSONObject("error").getString("code"))
                    assertTrue(result.getBoolean("mayHaveCompleted"))
                    val artifacts = result.getJSONArray("artifacts")
                    assertTrue("Known non-sensitive partial capture must be retained", artifacts.length() > 0)
                    for (i in 0 until artifacts.length()) {
                        val artifact = artifacts.getJSONObject(i)
                        assertTrue(artifact.getBoolean("partial"))
                        retrieve(client, result.getString("runId"), artifact)
                    }
                    val facts = client.call("evaluate", JSONObject().put("expression", "({events:window.events,value:document.querySelector('input').value})")).getJSONObject("result")
                    File(evidence, "paced-abort-result.json").writeText(result.toString(2))
                    File(evidence, "paced-abort-facts.json").writeText(facts.toString(2))
                    assertEquals(1, facts.getJSONArray("events").length())
                    assertEquals("A", facts.getString("value"))
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }

    @Test
    fun emptyPacedTypeDoesNotFocusOrEditButCapturesStep() =
        runCase("empty-type", "type", "", true) { _, result, facts ->
            assertTrue(result.getBoolean("success"))
            assertEquals(0, facts.getInt("focusCount"))
            assertEquals(0, facts.getJSONArray("events").length())
            assertEquals("old", facts.getString("value"))
            val artifacts = result.getJSONArray("artifacts")
            assertTrue((0 until artifacts.length()).any { artifacts.getJSONObject(it).getString("mimeType") == "image/png" })
        }

    @Test
    fun emptyPacedFillClearsOnce() =
        runCase("empty-fill", "fill", "", false) { _, result, facts ->
            assertTrue(result.getBoolean("success"))
            assertEquals("", facts.getString("value"))
            assertEquals(1, facts.getJSONArray("events").length())
        }
}
