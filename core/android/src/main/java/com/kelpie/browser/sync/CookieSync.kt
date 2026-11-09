package com.kelpie.browser.sync

import android.content.Context
import android.os.Build
import android.util.Log
import android.webkit.CookieManager
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import com.kelpie.browser.KelpieEnvironment
import com.kelpie.browser.browser.HistoryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File

/**
 * Process-wide entry point for cookie sync in the standalone Android app. It
 * runs inside the [com.kelpie.browser.network.KelpieNetworkService] lifetime,
 * only while signed in, and only against `CookieManager.getInstance()` — never
 * a partition profile. Embedded sessions never start it.
 */
object CookieSync {
    private const val TAG = "KelpieCookieSync"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val recent = RecentLoads(System::currentTimeMillis)

    @Volatile private var service: CookieSyncService? = null

    @Volatile private var source: WebViewCookieSource? = null

    /** `GET_COOKIE_INFO` is the only way to read cookies with their attributes. */
    fun supported(): Boolean = runCatching { WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO) }.getOrDefault(false)

    /** Called on the main thread when the network service starts. */
    fun start(context: Context) {
        if (!KelpieEnvironment.standalone(context) || !supported() || service != null) return
        val app = context.applicationContext
        // Resolve the default store on the main thread; the store thread then reuses it.
        val cookies = defaultEngine()
        val adapter = WebViewCookieSource(cookies, ::historyHosts, recent)
        val created =
            CookieSyncService(
                account = UOASyncAccount(scope),
                cookies = adapter,
                directory = File(app.filesDir, "sync"),
                discovery = NsdSyncDiscovery(app),
                subnets = AndroidSyncSubnets(app),
                transport = SyncHttpTransport(),
                deviceName = deviceName(),
                recent = recent,
                log = SyncLog { level, message -> Log.println(level, TAG, message) },
            )
        source = adapter
        service = created
        created.start()
    }

    /** Called when the network service stops; sync ends with it. */
    fun stop() {
        val running = service ?: return
        service = null
        source = null
        scope.launch { running.stop() }
    }

    /** A page in an unpartitioned standalone tab finished loading. */
    fun pageLoaded(url: String) {
        val parts = CoverageUrls.pageParts(url) ?: return
        val running = service
        if (running == null) recent.record(parts.first, url) else running.pageLoaded(parts.first, url)
    }

    /** `get-cookie-sync-status`: `supported` is false whenever sync is not running here. */
    suspend fun status(): Map<String, Any?> {
        val running = service?.status()
        val signedIn = com.kelpie.browser.account.UOAAccount.state.value.profile != null
        val reason =
            when {
                !KelpieEnvironment.standalone(KelpieEnvironment.app) -> "embedded"
                !supported() -> "webview-unsupported"
                !signedIn -> "signed-out"
                else -> null
            }
        val replica = running?.get("replica")

        @Suppress("UNCHECKED_CAST")
        val store = running?.get("store") as? Map<String, Any?> ?: emptyMap()
        return buildMap {
            put("supported", reason == null && replica != null)
            reason?.let { put("reason", it) }
            put("signedIn", signedIn)
            replica?.let { put("replica", it) }
            put("listening", running?.get("listening") == true)
            put("peers", running?.get("peers") ?: emptyList<Any>())
            put(
                "store",
                storeCounts.associateWith {
                    store[it] ?: if (it == "warming") {
                        false
                    } else if (it == "lastPurgeAt") {
                        null
                    } else {
                        0
                    }
                },
            )
        }
    }

    private val storeCounts = listOf("entries", "tombstones", "localOnly", "unapplied", "skipped", "warming", "lastPurgeAt")

    /**
     * The default store's coverage URL set: every metadata entry, history hosts
     * and recent page loads. Used by `get-cookies` with `all:true`.
     */
    suspend fun coverageUrls(): List<String> {
        val entries = service?.entryLocations().orEmpty()
        return CoverageUrls.build(entries, null, historyHosts(), recent.urls())
    }

    fun defaultEngine(): CookieInfoEngine = ManagerEngine(CookieManager.getInstance())

    /** A [CookieInfoEngine] over any WebView cookie manager (default store or a profile). */
    class ManagerEngine(
        private val manager: CookieManager,
    ) : CookieInfoEngine {
        override fun info(url: String): List<String> = CookieManagerCompat.getCookieInfo(manager, url)

        override fun set(
            url: String,
            header: String,
        ) = manager.setCookie(url, header)

        override fun flush() = manager.flush()
    }

    private fun historyHosts(): List<String> =
        HistoryStore.entries.value
            .asReversed()
            .mapNotNull { CoverageUrls.pageParts(it.url)?.first }
            .distinct()

    private fun deviceName(): String =
        "${Build.MANUFACTURER} ${Build.MODEL}"
            .trim()
            .filter { it >= ' ' && it != '\u007f' }
            .take(64)
}
