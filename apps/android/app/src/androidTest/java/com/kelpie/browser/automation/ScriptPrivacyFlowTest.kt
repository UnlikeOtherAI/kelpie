package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URLEncoder
import java.security.MessageDigest

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
                            "</title><label>Password<input type=\"$type\" autocomplete=\"off\" onfocus=\"window.__focusCount=(window.__focusCount||0)+1;$focus\" oninput=\"$input;window.__editFacts={hasFocus:document.hasFocus(),active:document.activeElement===this,type:this.type,autocomplete:this.autocomplete,focusCount:window.__focusCount||0};document.title='EDITED'\"></label>",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/privacy").toString())).getBoolean("success"))
                val end = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != title && System.nanoTime() < end) Thread.sleep(20)
                assertEquals("UTF-8 fixture title must commit before capture", title, client.core("tab.title", tab).getString("value"))
                val beforeFacts = focusFacts(client)
                val options =
                    JSONObject()
                        .put("target", JSONObject().put("label", "Password"))
                        .put("key", "__kelpie_focus_probe")
                        .put("policy", JSONObject().put("refuseSensitive", true))
                        .put("edit", JSONObject().put("action", "fill").put("text", "synthetic"))
                val generated = JSONObject(checkNotNull(ScriptNative.targetExpression(options.toString())))
                val expression = generated.getString("expression")
                val expressionHash =
                    MessageDigest
                        .getInstance("SHA-256")
                        .digest(expression.toByteArray(Charsets.UTF_8))
                        .joinToString("") { "%02x".format(it) }
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
                val afterFacts = focusFacts(client)
                java.io.File(evidence, "$case-focus-facts.json").writeText(
                    JSONObject()
                        .put("before", beforeFacts)
                        .put("after", afterFacts)
                        .put("generatedExpressionSha256", expressionHash)
                        .put("generatedPolicyPresent", expression.contains("\"refuseSensitive\":true"))
                        .toString(2),
                )
                java.io.File(evidence, "$case-result.json").writeText(result.toString(2))
                val status = client.call("get-script-status", JSONObject().put("runId", result.getString("runId")))
                java.io.File(evidence, "$case-status.json").writeText(status.toString(2))
                if (focus.isNotEmpty()) {
                    assertTrue("Focus handler did not run in the foreground document", afterFacts.getBoolean("hasFocus"))
                    assertTrue("Focus handler did not run", afterFacts.getInt("focusCount") > 0)
                    assertTrue("Sensitive focus must refuse before the input event", afterFacts.isNull("edit"))
                }
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

    private fun focusFacts(client: ScriptHttpFixture): JSONObject =
        client
            .call(
                "evaluate",
                JSONObject().put(
                    "expression",
                    """(()=>{const e=document.querySelector('input');const safe=x=>['text','password','off','current-password'].includes(x)?x:'other';const f=window.__editFacts;return {hasFocus:document.hasFocus(),active:document.activeElement===e,focusCount:Math.min(window.__focusCount||0,10),type:safe(e.type),autocomplete:safe(e.autocomplete),edit:f?{hasFocus:!!f.hasFocus,active:!!f.active,focusCount:Math.min(f.focusCount||0,10),type:safe(f.type),autocomplete:safe(f.autocomplete)}:null};})()""",
                ),
            ).getJSONObject("result")
}
