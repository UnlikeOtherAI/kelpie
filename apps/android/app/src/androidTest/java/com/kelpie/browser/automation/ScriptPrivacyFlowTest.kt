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
    fun inferredPasswordRefusalScrubsEarlierRawUriFormOutputsAndDiscardsCapture() {
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
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        "<!doctype html><meta name=\"viewport\" content=\"width=device-width\"><title>" + title +
                            "</title><label>Password<input type=\"password\" oninput=\"document.title='EDITED'\"></label>",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/privacy").toString())).getBoolean("success"))
                val end = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != title && System.nanoTime() < end) Thread.sleep(20)
                val script =
                    client
                        .script(
                            tab,
                            client.action("output").put("name", "before").put("source", "title"),
                            client.action("fill").put("target", JSONObject().put("label", "Password")).put("text", secret),
                        ).put("capture", JSONObject().put("formats", org.json.JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                java.io.File(evidence, "privacy-result.json").writeText(result.toString(2))
                assertFalse(result.getBoolean("success"))
                assertEquals("SENSITIVE_CAPTURE_REFUSED", result.getJSONObject("error").getString("code"))
                assertEquals(1, result.getInt("actionsExecuted"))
                assertEquals(0, result.getJSONArray("artifacts").length())
                val before = result.getJSONObject("outputs").getString("before")
                for (value in listOf(secret, uri, form)) assertFalse(before.contains(value))
                assertEquals(title, client.core("tab.title", tab).getString("value"))
                val status = client.call("get-script-status", JSONObject().put("runId", result.getString("runId")))
                java.io.File(evidence, "privacy-status.json").writeText(status.toString(2))
                assertEquals("SENSITIVE_CAPTURE_REFUSED", status.getJSONObject("runError").getString("code"))
                assertEquals(0, status.getJSONArray("artifacts").length())
                assertFalse(status.has("outputs"))
                for (value in listOf(secret, uri, form)) assertFalse(status.toString().contains(value))
            }
        }
    }
}
