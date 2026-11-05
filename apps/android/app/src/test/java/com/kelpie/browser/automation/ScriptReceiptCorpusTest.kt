package com.kelpie.browser.automation

import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.handlers.ScriptCallbackJson
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.io.File

/** Exercise the shared raw-JSON corpus through the same decoder and receipt fences as playback. */
class ScriptReceiptCorpusTest {
    @Test
    fun sharedReceiptAndPrivacyCases() {
        val file =
            generateSequence(File(checkNotNull(System.getProperty("user.dir"))).absoluteFile) { it.parentFile }
                .map { File(it, "tests/capture/ack-receipt-cases.json") }
                .firstOrNull { it.isFile }
        assertNotNull("Missing canonical receipt corpus", file)
        val root = OpenAIJson.parseObjectOrNull(checkNotNull(file).readText())
        assertNotNull(root)
        val corpus = OpenAIJson.toMap(checkNotNull(root))
        val token = corpus["expectedToken"] as String
        val cases = corpus["cases"] as List<*>
        assertEquals(52, cases.size)
        for (case in cases) {
            @Suppress("UNCHECKED_CAST")
            val item = case as Map<String, Any?>

            val callback = Json.encodeToString(OpenAIJson.encode(OpenAIJson.fromAny(item["result"])))
            val result = ScriptCallbackJson.parseObject(callback)
            val valid = scriptDispatchReceiptWellFormed(result, token)
            val receipt =
                if (!valid) {
                    "malformed"
                } else if (result["ok"] == true) {
                    "ack"
                } else {
                    "refusal"
                }
            assertEquals(item["name"].toString(), item["expectedReceipt"], receipt)
            val classification = ScriptTargetClassification()
            classification.started()
            val sensitive = result["sensitive"] as? Boolean
            classification.received(sensitive, result["sensitivityKnown"] as? Boolean)
            var protected = sensitive == true || classification.unknown()
            protectMalformedScriptReceipt(result, token) { protected = true }
            val privacy =
                when {
                    sensitive == true -> "known-positive"
                    protected -> "unknown"
                    else -> "known-negative"
                }
            assertEquals(item["name"].toString(), item["expectedPrivacy"], privacy)
        }
    }
}
