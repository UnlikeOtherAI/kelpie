package com.kelpie.browser.handlers

import com.kelpie.browser.browser.PartitionRegistry
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class MobileTabHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("get-tabs") { getTabs() }
        router.register("new-tab") { newTab(it) }
        router.register("switch-tab") { switchTab(it) }
        router.register("close-tab") { closeTab(it) }
        router.register("get-partitions") {
            successResponse(mapOf("partitions" to PartitionRegistry.listing(ctx.tabStore?.tabs?.value.orEmpty())))
        }
        router.register("delete-partition") { body ->
            val id = body["id"] as? String
            val tabs = ctx.tabStore
            when {
                id == null -> errorResponse("MISSING_PARAM", "id required")
                tabs == null -> errorResponse("NO_TAB_STORE", "Tab store not available")
                else -> PartitionRegistry.delete(id, tabs)
            }
        }
    }

    private suspend fun getTabs(): Map<String, Any?> {
        val tabStore = ctx.tabStore
        if (tabStore == null) {
            val wv = ctx.webView
            val tab =
                mapOf(
                    "id" to "0",
                    "windowId" to "main",
                    "url" to (wv?.url ?: ""),
                    "title" to (wv?.title ?: ""),
                    "active" to true,
                    "isLoading" to false,
                )
            return successResponse(
                mapOf("windowId" to "main", "tabs" to listOf(tab), "count" to 1, "activeTab" to "0"),
            )
        }

        val tabs =
            tabStore.tabs.value.map { tab ->
                tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value)
            }
        return successResponse(
            mapOf(
                "windowId" to "main",
                "tabs" to tabs,
                "count" to tabs.size,
                "activeTab" to (tabStore.activeTabId.value ?: ""),
            ),
        )
    }

    private fun newTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val url = body["url"] as? String
        val tab = try {
            val options = PartitionRegistry.validate(body)
            tabStore.addTab(url, options.partition, options.name)
        } catch (failure: PartitionRegistry.Failure) { return failure.response() }
        return successResponse(
            mapOf(
                "tabId" to tab.id,
                "tab" to tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value),
                "tabCount" to tabStore.tabs.value.size,
                "windowId" to "main",
            ),
        )
    }

    private fun switchTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val tabId =
            parseTabId(body)
                ?: return errorResponse("MISSING_PARAM", "tabId (UUID string) is required")
        val tab =
            tabStore.tabs.value.firstOrNull { it.id == tabId }
                ?: return errorResponse("TAB_NOT_FOUND", "No tab with id $tabId")
        tabStore.selectTab(tabId)
        return successResponse(
            mapOf(
                "tab" to tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value),
                "windowId" to "main",
            ),
        )
    }

    private fun closeTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val tabId =
            parseTabId(body)
                ?: return errorResponse("MISSING_PARAM", "tabId (UUID string) is required")
        val exists = tabStore.tabs.value.any { it.id == tabId }
        if (!exists) {
            return errorResponse("TAB_NOT_FOUND", "No tab with id $tabId")
        }
        tabStore.closeTab(tabId)
        return successResponse(
            mapOf(
                "closed" to tabId,
                "tabCount" to tabStore.tabs.value.size,
                "windowId" to "main",
            ),
        )
    }

    private fun parseTabId(body: Map<String, Any?>): String? = body["tabId"] as? String ?: body["id"] as? String

    private fun tabInfo(
        tab: com.kelpie.browser.browser.BrowserTab,
        activeTabId: String?,
    ): Map<String, Any?> =
        mapOf(
            "id" to tab.id,
            "windowId" to "main",
            "url" to tab.currentUrl,
            "title" to tab.pageTitle,
            "active" to (tab.id == activeTabId),
            "isLoading" to tab.isLoading,
        ) + buildMap {
            tab.name?.let { put("name", it) }
            tab.partition?.let { put("partition", it); put("persistent", true) }
        }
}
