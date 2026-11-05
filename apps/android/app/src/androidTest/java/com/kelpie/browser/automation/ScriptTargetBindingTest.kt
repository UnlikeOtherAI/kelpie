package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptTargetBindingTest : ScriptPublicFixture() {
    @Test
    fun sameDocumentSecondResolutionRetiresOldPrivateTokenWithoutInput() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)

                fun resolve(
                    token: String? = null,
                    dispatch: Boolean = false,
                ): JSONObject {
                    val options = JSONObject().put("key", "__kelpie_script_android_v1").put("target", client.target("Submit"))
                    if (token != null) options.put("token", token)
                    if (dispatch) options.put("dispatch", true)
                    // Only the authoritative fixed reader is evaluated. No test
                    // implementation of selection, hit testing or input exists.
                    val generated = JSONObject(checkNotNull(ScriptNative.targetExpression(options.toString())))
                    return client.call("evaluate", JSONObject().put("expression", generated.getString("expression"))).getJSONObject("result")
                }
                val first = resolve()
                assertTrue(first.getBoolean("ok"))
                val second = resolve()
                assertTrue(second.getBoolean("ok"))
                assertFalse(first.getString("token") == second.getString("token"))
                val retired = resolve(first.getString("token"), dispatch = true)
                assertFalse(retired.getBoolean("ok"))
                assertEquals("STALE_TARGET", retired.getString("error"))
                assertEquals("Ready", client.core("tab.title", tab).getString("value"))
                assertTrue(resolve(second.getString("token")).getBoolean("ok"))
                assertTrue(resolve(second.getString("token"), dispatch = true).getBoolean("ok"))
                assertEquals("Clicked:false", client.core("tab.title", tab).getString("value"))
            }
        }
    }

    private fun page(
        client: ScriptHttpFixture,
        server: MockWebServer,
        html: String,
    ): String {
        val tab = load(client, server)
        server.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody(html))
        assertTrue(client.call("navigate", JSONObject().put("url", server.url("/targets").toString())).getBoolean("success"))
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!client.core("tab.ready", tab, JSONObject().put("state", "complete")).getJSONObject("value").getBoolean("ready") &&
            System.nanoTime() < deadline
        ) {
            Thread.sleep(20)
        }
        ui.waitForIdle()
        return tab
    }

    @Test
    fun publicFillAndTypeUseExplicitAndImplicitLabelsWithNonBmpText() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab =
                    page(
                        client,
                        server,
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Fields</title>
                    <label>Name<input value="private-input-canary" oninput="document.title='Name:'+this.value"></label>
                    <label>Notes<textarea oninput="document.title='Notes:'+this.value">private-textarea-canary</textarea></label>""",
                    )

                fun edit(
                    action: String,
                    label: String,
                    text: String,
                ) = client.action(action).put("target", JSONObject().put("label", label)).put("text", text).put("sensitive", true)
                val wave = "\uD83C\uDF0A"
                val seal = "\uD83E\uDDAD"
                val result =
                    playRecorded(
                        client,
                        client.script(
                            tab,
                            edit("fill", "Name", "Alpha" + wave),
                            edit("type", "Name", "_Beta" + seal),
                            client.action("output").put("name", "name").put("source", "title"),
                            edit("fill", "Notes", "Text" + wave),
                            edit("type", "Notes", "_Tail" + seal),
                            client.action("output").put("name", "notes").put("source", "title"),
                        ),
                    )
                assertTrue("Typed input refused", result.getBoolean("success"))
                assertFalse(result.getJSONObject("outputs").getString("name").contains("Alpha" + wave))
                assertFalse(result.getJSONObject("outputs").getString("notes").contains("_Tail" + seal))
                assertEquals("Notes:Text" + wave + "_Tail" + seal, client.core("tab.title", tab).getString("value"))
                assertEquals("synthetic-coordinate", result.getString("inputGuarantee"))
            }
        }
    }

    @Test
    fun ambiguousDisabledAndCoveredPublicTargetsRefuseWithoutInput() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab =
                    page(
                        client,
                        server,
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Targets</title>
                    <style>button{position:absolute;width:110px;height:40px}</style>
                    <button style="left:10px;top:50px" onclick="document.title='WRONG'">Duplicate</button>
                    <button style="left:150px;top:50px" onclick="document.title='WRONG'">Duplicate</button>
                    <button disabled style="left:10px;top:150px" onclick="document.title='WRONG'">Disabled</button>
                    <button style="left:10px;top:250px" onclick="document.title='WRONG'">Covered</button>
                    <div style="position:absolute;left:10px;top:250px;width:110px;height:40px;z-index:10;background:black"></div>""",
                    )
                for ((name, codes) in listOf(
                    "Duplicate" to setOf("AMBIGUOUS_TARGET"),
                    "Disabled" to setOf("TARGET_NOT_FOUND", "TARGET_NOT_INTERACTABLE"),
                    "Covered" to setOf("TARGET_OBSCURED"),
                )) {
                    val result = playRecorded(client, client.script(tab, client.action("click").put("target", client.target(name))))
                    assertFalse(result.getBoolean("success"))
                    assertTrue(result.getJSONObject("error").getString("code") in codes)
                    assertEquals(0, result.getInt("actionsExecuted"))
                    assertEquals("Targets", client.core("tab.title", tab).getString("value"))
                }
            }
        }
    }
}
