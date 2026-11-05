package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URLEncoder

class ScriptPrivacyFlowTest : ScriptPublicFixture() {
    @Test
    fun inferredPasswordRefusalScrubsEarlierRawUriFormOutputsAndDiscardsCapture() = privacyCase("initial", "password", "")

    @Test
    fun focusAutocompleteRefusalScrubsEarlierOutputsWithoutEditing() = privacyCase("focus-autocomplete", "text", "this.autocomplete='current-password'")

    @Test
    fun focusPasswordRefusalScrubsEarlierOutputsWithoutEditing() = privacyCase("focus-password", "text", "this.type='password'")

    @Test
    fun inputAutocompleteCaptureRefusesAfterMutationAndDiscardsAllArtifacts() = privacyCase("input-autocomplete-capture", "text", "", "this.autocomplete='current-password'")

    @Test
    fun inputPasswordCaptureRefusesAfterMutationAndDiscardsAllArtifacts() = privacyCase("input-password-capture", "text", "", "this.type='password'")

    @Test
    fun inputAutocompleteWithoutCaptureCompletesAndScrubsEarlierOutputs() = privacyCase("input-autocomplete-nocapture", "text", "", "this.autocomplete='current-password'", false)

    @Test
    fun inputPasswordWithoutCaptureCompletesAndScrubsEarlierOutputs() = privacyCase("input-password-nocapture", "text", "", "this.type='password'", false)

    private fun privacyCase(
        case: String,
        type: String,
        focus: String,
        input: String = "",
        capture: Boolean = true,
    ) {
        val secret = "Aa b+!\uD83C\uDF0A"
        val form = URLEncoder.encode(secret, "UTF-8")
        val uri = form.replace("+", "%20").replace("%21", "!")
        val title = "raw:" + secret + " uri:" + uri + " form:" + form
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html; charset=utf-8").setBody(
                        "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>" + title +
                            "</title><label>Password<input type=\"$type\" autocomplete=\"off\" onfocus=\"$focus\" oninput=\"$input;document.title='EDITED'\"></label>",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/privacy").toString())).getBoolean("success"))
                val end = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != title && System.nanoTime() < end) Thread.sleep(20)
                assertEquals("UTF-8 fixture title must commit before capture", title, client.core("tab.title", tab).getString("value"))
                val script =
                    client
                        .script(
                            tab,
                            client.action("output").put("name", "before").put("source", "title"),
                            client.action("fill").put("target", JSONObject().put("label", "Password")).put("text", secret),
                            client.action("output").put("name", "after").put("source", "title"),
                        )
                if (capture) script.put("capture", JSONObject().put("formats", org.json.JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                java.io.File(evidence, "$case-result.json").writeText(result.toString(2))
                val status = client.call("get-script-status", JSONObject().put("runId", result.getString("runId")))
                java.io.File(evidence, "$case-status.json").writeText(status.toString(2))
                assertEquals(!capture, result.getBoolean("success"))
                if (capture) {
                    assertEquals("SENSITIVE_CAPTURE_REFUSED", result.getJSONObject("error").getString("code"))
                    assertFalse("No later action after privacy refusal", result.getJSONObject("outputs").has("after"))
                    if (input.isNotEmpty()) assertTrue(result.getBoolean("mayHaveCompleted"))
                } else {
                    assertEquals("EDITED", result.getJSONObject("outputs").getString("after"))
                }
                assertEquals(if (capture) 1 else 3, result.getInt("actionsExecuted"))
                assertEquals(0, result.getJSONArray("artifacts").length())
                val before = result.getJSONObject("outputs").getString("before")
                for (value in listOf(secret, uri, form)) assertFalse(before.contains(value))
                assertEquals(if (input.isEmpty()) title else "EDITED", client.core("tab.title", tab).getString("value"))
                if (capture) assertEquals("SENSITIVE_CAPTURE_REFUSED", status.getJSONObject("runError").getString("code")) else assertFalse(status.has("runError"))
                assertEquals(0, status.getJSONArray("artifacts").length())
                assertFalse(status.has("outputs"))
                for (value in listOf(secret, uri, form)) assertFalse(status.toString().contains(value))
            }
        }
    }
}
