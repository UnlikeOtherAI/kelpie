package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test

internal val scriptNoiseFixture =
    """<!doctype html><meta name="viewport" content="width=device-width"><title>CLI fixture</title>
    <canvas id="pixels"></canvas><script>
    const c=document.getElementById('pixels');c.width=innerWidth;c.height=innerHeight;
    const x=c.getContext('2d'),d=x.createImageData(c.width,c.height);let s=47;
    for(let i=0;i<d.data.length;i+=4){s^=s<<13;s^=s>>>17;s^=s<<5;
    d.data[i]=s&255;d.data[i+1]=(s>>>8)&255;d.data[i+2]=(s>>>16)&255;d.data[i+3]=255;}
    x.putImageData(d,0,0);</script>"""

class ScriptLargeArtifactTest : ScriptPublicFixture() {
    @Test
    fun largePngReconstructsIndependentlyThroughHttpDirectAndGenericMcp() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                server.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody(scriptNoiseFixture))
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/noise").toString())).getBoolean("success"))
                val script =
                    client
                        .script(
                            tab,
                            client.action("wait-ready").put("state", "complete").put("timeoutMs", 10_000),
                            client.action("screenshot"),
                        ).put("capture", JSONObject().put("formats", JSONArray().put("screenshots")).put("maxWidth", 640).put("maxBytes", 16_777_216))
                val result = playRecorded(client, script)
                assertTrue(result.getBoolean("success"))
                val artifacts = result.getJSONArray("artifacts")
                val artifact = (0 until artifacts.length()).map(artifacts::getJSONObject).first { it.getLong("byteLength") > 262_144 }
                retrieve(client, result.getString("runId"), artifact)
            }
        }
    }
}
