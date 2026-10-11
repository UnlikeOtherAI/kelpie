package com.kelpie.browser.network

/** Structural run scope, checked for every canonical request and rich extension invocation. */
object BrowserGatewayTabPolicy {
    fun permits(request: Map<String, Any?>, mutates: Boolean, allowActions: Boolean,
        pinned: String?, active: String, existing: Set<String>): Boolean {
        val tab = request["tabId"] as? String
        val nestedTab = (request["params"] as? Map<*, *>)?.get("tabId") as? String
        return (tab == null || tab in existing) && (nestedTab == null || nestedTab in existing) &&
            (allowActions || !mutates) && (pinned == null ||
            (active == pinned && (tab == null || tab == pinned) && (nestedTab == null || nestedTab == pinned)))
    }
}
