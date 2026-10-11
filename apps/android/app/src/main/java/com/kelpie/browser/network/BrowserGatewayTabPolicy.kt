package com.kelpie.browser.network

/** Structural run scope, checked for every canonical request and rich extension invocation. */
object BrowserGatewayTabPolicy {
    fun permitsDispatch(
        method: String,
        params: Map<String, Any?>,
        pinned: String?,
        active: String,
    ): Boolean {
        if (pinned != null && active != pinned) return false
        if (method in setOf("switch-tab", "close-tab", "new-tab")) return true
        val target = params["tabId"] as? String
        return target == null || target == active
    }

    fun permits(
        request: Map<String, Any?>,
        mutates: Boolean,
        allowActions: Boolean,
        pinned: String?,
        active: String,
        existing: Set<String>,
    ): Boolean {
        val tab = request["tabId"] as? String
        val nestedTab = (request["params"] as? Map<*, *>)?.get("tabId") as? String
        return (tab == null || tab in existing) &&
            (nestedTab == null || nestedTab in existing) &&
            (allowActions || !mutates) &&
            (
                pinned == null ||
                    (active == pinned && (tab == null || tab == pinned) && (nestedTab == null || nestedTab == pinned))
            )
    }
}
