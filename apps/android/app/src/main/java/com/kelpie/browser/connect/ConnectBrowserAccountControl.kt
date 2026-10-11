package com.kelpie.browser.connect

import android.content.Context
import com.kelpie.browser.handlers.BrowserManagementHandler
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.InteractionHandler
import com.kelpie.browser.handlers.NavigationHandler
import com.kelpie.browser.handlers.ScreenshotHandler
import com.kelpie.browser.handlers.ScrollHandler
import com.kelpie.browser.llm.LLMHandler
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Canonical account controls execute through the process-wide browser gateway. */
class ConnectBrowserAccountControl(
    private val context: HandlerContext,
    private val appContext: Context,
    private val authority: (Map<String, Any?>) -> Boolean,
) {
    suspend fun execute(
        command: Map<String, Any?>,
        input: Map<String, Any?>,
    ): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        val request =
            input["request"] as? Map<String, Any?>
                ?: return mapOf("response" to controlFailure("INVALID_ARGUMENTS"))
        val method =
            request["method"] as? String
                ?: return mapOf("response" to controlFailure("INVALID_ARGUMENTS"))
        if (method !in ACCOUNT_CONTROL_METHODS) return mapOf("response" to controlFailure("UNSUPPORTED"))
        val unbound = method in setOf("capabilities", "documentation", "tabs.list", "tabs.new")
        if (method in setOf("tabs.new", "tab.goto") && isAccountDestination(request["params"] as? Map<*, *>)) {
            return mapOf("response" to controlFailure("ACCOUNT_SURFACE_FORBIDDEN"))
        }
        val tabId = command["tabId"] as? String
        val expected = command["tabVersion"] as? String
        if (unbound) {
            if (tabId != null || expected != null) return mapOf("response" to controlFailure("TAB_PIN_MISMATCH"))
        } else {
            if (tabId == null || expected == null || request["tabId"] != tabId) return mapOf("response" to controlFailure("TAB_PIN_MISMATCH"))
            if (runCatching { version(tabId) }.getOrNull() != expected) return mapOf("response" to controlFailure("STALE_DOCUMENT"))
            if (isAccountSurface(tabId)) return mapOf("response" to controlFailure("ACCOUNT_SURFACE_FORBIDDEN"))
        }
        val gateway = context.browserGateway ?: return mapOf("response" to controlFailure("UNAVAILABLE"))
        val scope = currentCoroutineContext()
        val selected = context.tabStore?.activeTabId?.value ?: "0"
        if (!unbound && method != "tabs.select" && selected != tabId) {
            return mapOf("response" to controlFailure("TAB_NOT_ACTIVE"))
        }
        val targetTab =
            tabId?.let { id ->
                context.tabStore
                    ?.tabs
                    ?.value
                    ?.firstOrNull { it.id == id }
            }
        if (!unbound && targetTab == null) return mapOf("response" to controlFailure("TAB_NOT_FOUND"))
        val navigationLease =
            if (method == "tab.goto" && targetTab != null) {
                val params = request["params"] as? Map<*, *>
                ConnectNavigationLease(expected!!, params?.get("url") as? String)
            } else {
                null
            }

        fun navigationAuthority(): Boolean = accountOwnerAuthority(scope, command, tabId, method == "tabs.select")
        val isolated =
            targetTab?.let { tab ->
                HandlerContext(context.browserRetirement).apply {
                    webView = tab.webView
                    tabStore = context.tabStore
                    scriptPlaybackState = context.scriptPlaybackState
                    remoteDocumentGuard = {
                        scope[kotlinx.coroutines.Job]?.isActive == true &&
                            authority(command) &&
                            context.tabStore
                                ?.tabs
                                ?.value
                                ?.any { it === tab } == true &&
                            tab.documentVersion == expected &&
                            !tab.isLoading &&
                            (method == "tabs.select" || context.tabStore?.activeTabId?.value == tab.id)
                    }
                    if (navigationLease != null) {
                        remoteNavigationStart = { navigationLease.arm(tab.documentVersion, navigationAuthority()) }
                        remoteNavigationReadGuard = {
                            navigationLease.allowsRead(tab.documentVersion, tab.isLoading, navigationAuthority())
                        }
                        remoteNavigationWaitGuard = {
                            navigationLease.allowsWait(tab.documentVersion, navigationAuthority())
                        }
                        tab.remoteNavigationLease = navigationLease
                    }
                }
            }
        val targetRouter =
            isolated?.let { target ->
                Router().apply {
                    browserGateway = gateway
                    handlerContext = target
                    scriptPlaybackState = context.scriptPlaybackState
                    NavigationHandler(target).register(this)
                    ScreenshotHandler(target).register(this)
                    InteractionHandler(target).register(this)
                    ScrollHandler(target).register(this)
                    LLMHandler(target).register(this)
                    ConnectSnapshot(target).register(this)
                    BrowserManagementHandler(target, appContext).register(this)
                }
            }
        val newTabRouter =
            if (method == "tabs.new") {
                val unboundContext =
                    HandlerContext(context.browserRetirement).apply {
                        tabStore = context.tabStore
                        browserGateway = gateway
                    }
                Router().apply {
                    handlerContext = unboundContext
                    BrowserManagementHandler(unboundContext, appContext).register(this)
                }
            } else {
                null
            }
        val allowedDestination = { params: Map<String, Any?> ->
            val url = params["url"] as? String
            url == null || !isAccountURL(url)
        }
        val dispatch: suspend (String, Map<String, Any?>) -> Map<String, Any?> = { nativeMethod, params ->
            if (!accountAuthority(scope, command, tabId, expected, method == "tabs.select")) {
                errorResponse("TAB_CHANGED", "The controlled page changed")
            } else if ((nativeMethod == "navigate" || nativeMethod == "new-tab") && !allowedDestination(params)) {
                errorResponse("ACCOUNT_SURFACE_FORBIDDEN", "Account sign-in surfaces are unavailable")
            } else if (targetRouter == null) {
                errorResponse("TAB_NOT_FOUND", "The controlled page is unavailable")
            } else {
                withContext(Dispatchers.Main.immediate) {
                    val result =
                        if (nativeMethod == "browser-control-evaluate") {
                            val expression = params["expression"] as? String ?: ""
                            val value = isolated!!.evaluateJSReturningJSON(expression)
                            if (value.isEmpty()) {
                                errorResponse("RENDERER_ERROR", "The fixed reader returned no JSON object")
                            } else {
                                successResponse(mapOf("result" to value))
                            }
                        } else {
                            targetRouter.handle(nativeMethod, params, fromGateway = true).second
                        }
                    val remainsAuthorized =
                        if (navigationLease != null && targetTab != null && nativeMethod == "navigate") {
                            navigationLease.allowsRead(
                                targetTab.documentVersion,
                                targetTab.isLoading,
                                navigationAuthority(),
                            )
                        } else {
                            accountAuthority(scope, command, tabId, expected, method == "tabs.select")
                        }
                    if (!remainsAuthorized) {
                        errorResponse("TAB_CHANGED", "The controlled page changed")
                    } else {
                        result
                    }
                }
            }
        }
        val invoke =
            suspend {
                val jobDispatch: (suspend (String, Map<String, Any?>) -> Map<String, Any?>)? =
                    when {
                        method == "tabs.new" -> { nativeMethod, params ->
                            if (nativeMethod != "new-tab" || !authority(command)) {
                                errorResponse("JOB_AUTHORITY_CHANGED", "The browser job is no longer authorized")
                            } else if (!allowedDestination(params)) {
                                errorResponse("ACCOUNT_SURFACE_FORBIDDEN", "Account sign-in surfaces are unavailable")
                            } else {
                                withContext(Dispatchers.Main.immediate) {
                                    currentCoroutineContext().ensureActive()
                                    if (!authority(command)) {
                                        errorResponse("JOB_AUTHORITY_CHANGED", "The browser job is no longer authorized")
                                    } else {
                                        newTabRouter!!.handle(nativeMethod, params, fromGateway = true).second
                                    }
                                }
                            }
                        }
                        unbound || method == "tabs.select" -> null
                        else -> dispatch
                    }
                gateway.accountControl(request, { accountAuthority(scope, command, tabId, expected, method == "tabs.select") }, jobDispatch).orEmpty()
            }
        val response =
            try {
                if (method in setOf("tabs.select", "tabs.new", "tabs.close")) {
                    NessieConnection.changeTabRemotelySuspending {
                        invoke()
                    }
                } else {
                    invoke()
                }
            } finally {
                if (navigationLease != null && targetTab != null && targetTab.remoteNavigationLease === navigationLease) {
                    targetTab.remoteNavigationLease = null
                }
            }
        if ((method == "tabs.select" || method == "tabs.new") && response["ok"] == true) {
            val canonicalValue = response["value"] as? Map<*, *>
            val claimed = if (method == "tabs.select") tabId else canonicalValue?.get("id") as? String
            if (claimed != null) NessieConnection.claimTab(claimed)
        }
        val canonical = response.toMutableMap()
        if (method == "capabilities" && canonical["ok"] == true) {
            @Suppress("UNCHECKED_CAST")
            val value = (canonical["value"] as? Map<String, Any?>)?.toMutableMap()
            if (value != null) {
                value["extensions"] = emptyList<String>()
                value["methods"] = (value["methods"] as? List<*>)?.filter { it in ACCOUNT_CONTROL_METHODS }.orEmpty()
                canonical["value"] = value
            }
        }
        val output = mutableMapOf<String, Any?>("response" to canonical)
        if (method == "tabs.list" && canonical["ok"] == true) {
            @Suppress("UNCHECKED_CAST")
            val ids =
                (canonical["value"] as? List<Map<String, Any?>>)
                    ?.mapNotNull { it["id"] as? String }
                    ?.toSet()
                    .orEmpty()
            output["tabs"] =
                tabs().filter { it["tabId"] in ids }.mapNotNull { tab ->
                    val id = tab["tabId"] as? String ?: return@mapNotNull null
                    val version = tab["tabVersion"] as? String ?: return@mapNotNull null
                    mapOf("tabId" to id, "tabVersion" to version)
                }
        } else if (method == "tabs.new" && canonical["ok"] == true) {
            @Suppress("UNCHECKED_CAST")
            val value = canonical["value"] as? Map<String, Any?>
            val id = (value?.get("id") ?: value?.get("tabId")) as? String
            val tab = tabs().firstOrNull { it["tabId"] == id }
            if (id != null && tab != null) output["tab"] = mapOf("tabId" to id, "tabVersion" to tab["tabVersion"])
        } else if (tabId != null) {
            val current = runCatching { version(tabId) }.getOrNull()
            if (canonical["ok"] == true || current == expected) {
                if (current != null) output["tab"] = mapOf("tabId" to tabId, "tabVersion" to current)
            }
        }
        return output
    }

    private suspend fun accountAuthority(
        scope: kotlin.coroutines.CoroutineContext,
        command: Map<String, Any?>,
        tabId: String?,
        expected: String?,
        allowInactiveSelection: Boolean = false,
    ): Boolean {
        if (!accountOwnerAuthority(scope, command, tabId, allowInactiveSelection)) return false
        if (tabId != null && expected != null) {
            return runCatching {
                version(tabId) == expected && !isAccountSurface(tabId)
            }.getOrDefault(false)
        }
        return true
    }

    private fun accountOwnerAuthority(
        scope: kotlin.coroutines.CoroutineContext,
        command: Map<String, Any?>,
        tabId: String?,
        allowInactiveSelection: Boolean = false,
    ): Boolean {
        if (scope[kotlinx.coroutines.Job]?.isActive != true || !authority(command)) return false
        if (tabId == null) return true
        return runCatching {
            context.tabStore
                ?.tabs
                ?.value
                ?.any { it.id == tabId } == true &&
                !isAccountSurface(tabId) &&
                (allowInactiveSelection || context.tabStore?.activeTabId?.value == tabId)
        }.getOrDefault(false)
    }

    private fun controlFailure(code: String): Map<String, Any?> =
        mapOf(
            "version" to 1,
            "ok" to false,
            "error" to
                mapOf(
                    "code" to code,
                    "message" to "Browser request refused; observe the page before continuing.",
                    "mayHaveCompleted" to false,
                ),
        )

    private fun isAccountSurface(tabId: String): Boolean {
        val url = tabs().firstOrNull { it["tabId"] == tabId }?.get("url") as? String ?: return false
        return isAccountURL(url)
    }

    private fun isAccountDestination(params: Map<*, *>?): Boolean {
        val url = params?.get("url") as? String ?: return false
        return isAccountURL(url)
    }

    private fun isAccountURL(url: String): Boolean =
        runCatching {
            java.net
                .URI(url)
                .host
                .equals("authentication.unlikeotherai.com", ignoreCase = true)
        }.getOrDefault(false)

    private companion object {
        val ACCOUNT_CONTROL_METHODS =
            setOf(
                "capabilities",
                "documentation",
                "tabs.list",
                "tabs.new",
                "tabs.select",
                "tabs.close",
                "tab.snapshot",
                "tab.screenshot",
                "tab.goto",
                "tab.click",
                "tab.type",
                "page.press",
                "page.scroll",
            )
    }

    val supportsControlV1: Boolean get() = context.browserGateway != null

    private fun tabs(): List<Map<String, Any?>> =
        context.tabStore?.tabs?.value?.map {
            mapOf(
                "tabId" to it.id,
                "tabVersion" to it.documentVersion,
                "url" to it.currentUrl,
                "title" to it.pageTitle,
                "loading" to it.isLoading,
                "active" to (it.id == context.tabStore?.activeTabId?.value),
            )
        } ?: emptyList()

    private fun version(tabId: String): String {
        val tab =
            context.tabStore
                ?.tabs
                ?.value
                ?.firstOrNull { it.id == tabId } ?: error("Tab not found")
        check(!tab.isLoading) { "Tab is navigating; refresh its snapshot" }
        return tab.documentVersion
    }
}
