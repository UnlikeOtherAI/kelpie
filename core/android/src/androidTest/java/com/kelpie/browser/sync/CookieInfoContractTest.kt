package com.kelpie.browser.sync

import android.util.Log
import android.webkit.CookieManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Probe: dumps what a real WebView returns from getCookieInfo for each cookie shape sync needs. */
@RunWith(AndroidJUnit4::class)
class CookieInfoContractTest {
    @Test
    fun dumpCookieInfoShapes() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO))
        instrumentation.runOnMainSync {
            val manager = CookieManager.getInstance()
            val host = "https://www.probe.kelpie-sync.test"
            val future = "Wed, 01 Jan 2031 00:00:00 GMT"
            listOf(
                "hostonly=1; Path=/; Secure; HttpOnly; SameSite=Strict; Expires=$future",
                "domaincookie=2; Domain=www.probe.kelpie-sync.test; Path=/; SameSite=Lax; Expires=$future",
                "parentcookie=3; Domain=probe.kelpie-sync.test; Path=/",
                "pathcookie=4; Path=/account",
                "nonecookie=5; Secure; SameSite=None; Path=/",
                "maxage=6; Max-Age=3600; Path=/",
                "chips=7; Secure; SameSite=None; Path=/; Partitioned",
                "nosamesite=8; Path=/",
            ).forEach { manager.setCookie("$host/", it) }
            manager.flush()
            for (url in listOf("$host/", "$host/account", "https://probe.kelpie-sync.test/", "http://www.probe.kelpie-sync.test/")) {
                val info = CookieManagerCompat.getCookieInfo(manager, url)
                Log.i(TAG, "url=$url count=${info.size}")
                info.forEach { Log.i(TAG, "  $it") }
                instrumentation.sendStatus(0, android.os.Bundle().apply { putString("probe", "$url -> $info") })
            }
            manager.removeAllCookies(null)
            manager.flush()
        }
    }

    private companion object {
        const val TAG = "CookieInfoProbe"
    }
}
