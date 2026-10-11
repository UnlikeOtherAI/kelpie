package com.kelpie.browser.network

/** Selects only an authoritative extension descriptor; the native gateway still validates its arguments. */
object BrowserGatewayReentrant {
    fun permits(request: Map<String, Any?>, descriptors: List<Map<String, Any?>>, methods: Set<String>): Boolean {
        if (request["method"] != "tools/call") return false
        val params = request["params"] as? Map<*, *> ?: return false
        val named = params["name"] as? String ?: return false
        val name = if (named == "kelpie_extension") (params["arguments"] as? Map<*, *>)?.get("name") else named
        return descriptors.any { it["name"] == name && it["method"] in methods }
    }
}
