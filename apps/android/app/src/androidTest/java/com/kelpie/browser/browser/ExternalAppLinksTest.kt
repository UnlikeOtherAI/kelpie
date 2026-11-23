package com.kelpie.browser.browser

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalAppLinksTest {
    @Test
    fun classifiesAppLinks() {
        listOf("slack://open?team=T1", "zoommtg://zoom.us/join", "mailto:a@example.com", "intent://x#Intent;end")
            .forEach { assertTrue(it, ExternalAppLinks.isAppLink(Uri.parse(it))) }
        listOf("https://slack.com", "http://localhost:8420", "about:blank", "data:text/plain,hi", "blob:https://a.test/1")
            .forEach { assertFalse(it, ExternalAppLinks.isAppLink(Uri.parse(it))) }
    }

    @Test
    fun intentLinksAreRebuiltWithoutComponentSelectorExtrasOrFlags() {
        val url =
            "intent://open/channel#Intent;scheme=slack;package=com.Slack;component=com.Slack/.Evil;" +
                "launchFlags=0x10000000;S.secret=x;S.browser_fallback_url=https%3A%2F%2Fslack.com%2Fapp;end"
        val intent = requireNotNull(ExternalAppLinks.intentFor(url))
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals(Uri.parse("slack://open/channel"), intent.data)
        assertEquals("com.Slack", intent.`package`)
        assertNull(intent.component)
        assertNull(intent.selector)
        assertNull(intent.extras)
        assertEquals(0, intent.flags)
        assertTrue(intent.hasCategory(Intent.CATEGORY_BROWSABLE))
        assertEquals("https://slack.com/app", ExternalAppLinks.fallbackUrl(url))
    }

    @Test
    fun refusesLocalDataAndUnsafeFallbacks() {
        assertNull(ExternalAppLinks.intentFor("intent://x#Intent;scheme=content;package=com.a;end"))
        assertNull(ExternalAppLinks.intentFor("intent://x#Intent;scheme=file;end"))
        assertNull(ExternalAppLinks.fallbackUrl("intent://x#Intent;scheme=a;S.browser_fallback_url=javascript%3Aalert(1);end"))
        assertEquals("https://kilomayo.slack.com", ExternalAppLinks.origin("https://KiloMayo.slack.com/ssb/redirect"))
    }
}
