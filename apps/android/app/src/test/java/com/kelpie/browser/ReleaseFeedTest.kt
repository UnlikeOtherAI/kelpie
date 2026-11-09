package com.kelpie.browser

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class ReleaseFeedTest {
    private fun entry(
        version: String,
        target: String = "android",
        draft: Boolean = false,
    ): JSONObject {
        val item =
            JSONObject()
                .put("target", target)
                .put("version", version)
                .put("url", "https://github.com/UnlikeOtherAI/kelpie/releases/download/tag/kelpie.apk")
        return JSONObject()
            .put("draft", draft)
            .put("prerelease", false)
            .put("body", "<!-- kelpie-update: $item -->")
    }

    @Test
    fun componentVersionsCompareNumerically() {
        val feed = JSONArray().put(entry("0.2.9")).put(entry("0.2.10")).put(entry("0.2.2"))
        assertEquals("0.2.10", ReleaseFeed.newest(feed, "0.2.0")?.version)
        assertNull(ReleaseFeed.newest(feed, "0.2.10"))
        assertNull(ReleaseFeed.newest(feed, "0.3.0"))
        assertNull(ReleaseFeed.newest(feed, "invalid"))
    }

    @Test
    fun draftsUnrelatedAndMalformedEntriesDoNotHideAValidUpdate() {
        val feed =
            JSONArray()
                .put(entry("9.0.0", draft = true))
                .put(entry("9.0.0", target = "ios"))
                .put(JSONObject().put("draft", false).put("prerelease", false).put("body", "<!-- kelpie-update: {broken} -->"))
                .put(entry("0.2.1"))
        assertEquals("0.2.1", ReleaseFeed.newest(feed, "0.2.0")?.version)
    }

    @Test
    fun rejectsUnsafeOrIncompatibleUpdateRoutes() {
        for (url in listOf(
            "file:///tmp/update.apk",
            "https://github.com.evil.example/update.apk",
            "https://github.com/UnlikeOtherAI/kelpie/releases/download/tag/../update.apk",
            "https://github.com/UnlikeOtherAI/kelpie/releases/download/tag/Kelpie-simulator.zip",
        )) {
            assertFalse(ReleaseFeed.allowedURL(url))
        }
    }
}
