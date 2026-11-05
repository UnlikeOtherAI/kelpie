package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptObservationFlowTest : ScriptPublicFixture() {
    @Test
    fun scopedValueFreeReadsNestedExtractionMetadataAndReadinessUseRealWebView() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val html =
                    """<!doctype html><meta name="viewport" content="width=device-width"><title>Observations</title>
                    <meta name="author" content="Fixture Publisher"><script type="application/ld+json">
                    {"@type":"Article","headline":"Publisher Headline","privateArbitraryField":"not-publisher-metadata"}</script>
                    <aside>Outside Sentinel</aside><main id="scope"><h1>Public Scope</h1>
                    <button id="one">Unique action</button><input aria-invalid="true" value="private-input-canary">
                    <textarea>private-textarea-canary</textarea><div contenteditable>private-editor-canary</div>
                    <div aria-busy="true">Loading label</div><div role="dialog">Dialog label</div>
                    <article class="record"><h2 class="name">Alpha</h2><a href="/alpha">Alpha link</a></article>
                    <article class="record"><h2 class="name">Beta</h2><a href="/beta">Beta link</a></article>
                    <div id="hidden" style="display:none">Hidden</div><p>""" + "Public long text ".repeat(100) + "</p></main>"
                server.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody(html))
                val url = server.url("/observations").toString()
                assertTrue(client.call("navigate", JSONObject().put("url", url)).getBoolean("success"))
                val deadline = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != "Observations" && System.nanoTime() < deadline) Thread.sleep(20)
                val snapshot =
                    client
                        .core(
                            "tab.snapshot",
                            tab,
                            JSONObject()
                                .put("scope", "#scope")
                                .put("prioritize", true)
                                .put("maxChars", 256)
                                .put("maxElements", 1),
                        ).getJSONObject("value")
                assertEquals("button", snapshot.getJSONArray("elements").getJSONObject(0).getString("role"))
                assertEquals("Unique action", snapshot.getJSONArray("elements").getJSONObject(0).getString("name"))
                for (privateValue in listOf("private-input-canary", "private-textarea-canary", "private-editor-canary", "Outside Sentinel")) assertFalse(snapshot.toString().contains(privateValue))
                assertTrue(snapshot.getBoolean("truncated"))
                val fields =
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("name", "rows")
                                .put("selector", ".record")
                                .put("multiple", true)
                                .put(
                                    "fields",
                                    JSONArray()
                                        .put(JSONObject().put("name", "name").put("selector", ".name"))
                                        .put(JSONObject().put("name", "link").put("selector", "a").put("source", "href")),
                                ),
                        ).put(JSONObject().put("name", "missing").put("selector", ".absent"))
                        .put(JSONObject().put("name", "duplicate").put("selector", ".name"))
                val extraction = client.core("tab.extract", tab, JSONObject().put("scope", "#scope").put("fields", fields).put("metadata", true)).getJSONObject("value")
                assertEquals(url, extraction.getString("url"))
                assertEquals("unavailable", extraction.getJSONObject("documentRevision").getString("availability"))
                val extracted = extraction.getJSONArray("fields")
                val records = extracted.getJSONObject(0).getJSONArray("records")
                assertEquals(2, records.length())
                assertEquals(
                    "Alpha",
                    records
                        .getJSONArray(0)
                        .getJSONObject(0)
                        .getJSONArray("values")
                        .getString(0),
                )
                assertEquals(
                    "Beta",
                    records
                        .getJSONArray(1)
                        .getJSONObject(0)
                        .getJSONArray("values")
                        .getString(0),
                )
                assertEquals(
                    "/alpha",
                    records
                        .getJSONArray(0)
                        .getJSONObject(1)
                        .getJSONArray("values")
                        .getString(0),
                )
                assertEquals("missing", extracted.getJSONObject(1).getString("status"))
                assertEquals("ambiguous", extracted.getJSONObject(2).getString("status"))
                val metadata = extraction.getJSONArray("metadata")
                assertTrue(metadata.length() > 0)
                assertFalse(metadata.toString().contains("not-publisher-metadata"))
                for (index in 0 until metadata.length()) {
                    assertEquals("publisher-claim", metadata.getJSONObject(index).getString("authority"))
                    assertTrue(metadata.getJSONObject(index).has("selector"))
                    assertTrue(metadata.getJSONObject(index).has("attribute"))
                }
                val ready = client.core("tab.ready", tab, JSONObject().put("state", "complete").put("selector", "#one")).getJSONObject("value")
                assertTrue(ready.getBoolean("ready"))
                val duplicate = client.core("tab.ready", tab, JSONObject().put("selector", ".name")).getJSONObject("value")
                assertFalse(duplicate.getBoolean("ready"))
                assertEquals(2, duplicate.getInt("matches"))
                assertFalse(client.core("tab.ready", tab, JSONObject().put("selector", "#hidden")).getJSONObject("value").getBoolean("ready"))
                val status = client.core("tab.status", tab).getJSONObject("value")
                assertEquals("complete", status.getString("documentState"))
                assertEquals("unavailable", status.getJSONObject("network").getString("availability"))
                assertEquals("unavailable", status.getJSONObject("errors").getString("availability"))
                assertEquals(1, status.getInt("dialogs"))
                assertEquals(1, status.getInt("busyRegions"))
                assertEquals(1, status.getInt("invalidControls"))
                val capabilities = client.call("get-capabilities").getJSONObject("scriptWorkflow")
                assertFalse(capabilities.getJSONObject("lightpanda").getBoolean("available"))
                assertFalse(capabilities.getJSONObject("webMcp").getBoolean("available"))
            }
        }
    }
}
