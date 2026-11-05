package com.kelpie.browser.automation

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the actual linked JNI/C ABI, not a Kotlin schema or matcher copy. */
@RunWith(AndroidJUnit4::class)
class ScriptNativeContractTest {
    @Test
    fun validationAndNumericalPresentationUseSharedCore() {
        val valid = JSONObject(ScriptNative.validate("""{"version":1,"tabId":"tab","actions":[{"action":"wait","ms":1}]}"""))
        assertTrue(valid.getBoolean("valid"))
        assertEquals(0, valid.getJSONObject("script").getInt("defaultWaitBetweenActions"))
        for (invalid in listOf(
            """{"version":2,"tabId":"tab","actions":[{"action":"wait","ms":1}]}""",
            """{"version":1,"tabId":"tab","actions":[{"action":"evaluate","script":"alert(1)"}]}""",
            """{"version":1,"tabId":"tab","actions":[{"action":"wait","ms":1}],"capture":{"formats":["gif"],"maxBytes":1023}}""",
        )) {
            assertFalse(JSONObject(ScriptNative.validate(invalid)).getBoolean("valid"))
        }
        assertNotNull(ScriptNative.targetExpression("""{"target":{"role":"button","name":"Go","exact":true},"key":"contract","observe":true}"""))
        val start = ScriptNative.pointerPosition(10.0, 20.0, 210.0, 120.0, true, 0.0, 500.0)
        val end = ScriptNative.pointerPosition(10.0, 20.0, 210.0, 120.0, false, 500.0, 500.0)
        assertEquals(10.0, start[0], 0.0001)
        assertEquals(20.0, start[1], 0.0001)
        assertEquals(210.0, end[0], 0.0001)
        assertEquals(120.0, end[1], 0.0001)
        val tap = ScriptNative.tapPresentation(700.0, 700.0, true, true)
        assertEquals(0.0, tap[1], 0.0001)
    }

    @Test
    fun nativeRedactorFoldsOnlyEncodedHexDigitsAndProjectsExtraction() {
        fun scrub(
            secret: String,
            values: List<String>,
        ): List<String> {
            val request =
                JSONObject()
                    .put("outputs", JSONObject().put("nested", JSONObject().put("values", JSONArray(values))))
                    .put("extractionNames", JSONArray())
                    .put("secrets", JSONArray(listOf(secret)))
            val result = JSONObject(checkNotNull(ScriptNative.redactOutputs(request.toString())))
            assertTrue(result.getBoolean("ok"))
            val output = result.getJSONObject("outputs").getJSONObject("nested").getJSONArray("values")
            return (0 until output.length()).map(output::getString)
        }
        val encoded = scrub("Aa b+!", listOf("Aa%20b%2b!", "Aa+b%2b%21", "Aa%20b%2B!", "aa b+!", "Aa%20B%2b!"))
        assertEquals(listOf("[redacted]", "[redacted]", "[redacted]", "aa b+!", "Aa%20B%2b!"), encoded)
        assertEquals(
            listOf("[redacted]", "[redacted]", "token%2fValue"),
            scrub("token%2FValue", listOf("token%2FValue", "token%252FValue", "token%2fValue")),
        )
        val projector = ScriptRedactor()
        projector.add("private")
        val output =
            projector.redact(
                mapOf("records" to mapOf("url" to "https://example.test/private", "pageSource" to "private")),
                listOf("records"),
            )
        assertFalse(output.toString().contains("private"))
        assertFalse(output.toString().contains("pageSource"))
        assertTrue(output.toString().contains("[redacted]"))
    }

    @Test
    fun standardUtf8RoundTripsNonBmpAndEscapedNulWithoutPrefixTruncation() {
        val wave = "\uD83C\uDF0A"
        val seal = "\uD83E\uDDAD"
        val value = wave + seal + "left\u0000right"
        val request =
            JSONObject()
                .put("outputs", JSONObject().put("value", value))
                .put("extractionNames", JSONArray())
                .put("secrets", JSONArray(listOf(seal)))
                .toString()
        repeat(100) {
            val response = JSONObject(checkNotNull(ScriptNative.redactOutputs(request)))
            assertTrue(response.getBoolean("ok"))
            assertEquals(wave + "[redacted]left\u0000right", response.getJSONObject("outputs").getString("value"))
        }
        assertEquals(null, ScriptNative.redactOutputs(request + '\u0000' + "ignored"))
        assertEquals(null, ScriptNative.redactOutputs(request + '\uD800'))
        val validScript = """{"version":1,"tabId":"tab","actions":[{"action":"commentary","text":"\ud83c\udf0a\ud83e\uddad"}]}"""
        assertTrue(JSONObject(ScriptNative.validate(validScript)).getBoolean("valid"))
        assertFalse(JSONObject(ScriptNative.validate(validScript + '\u0000')).getBoolean("valid"))
    }
}
