package com.kelpie.browser.handlers

/** Replacement documents may redirect; a changed fragment may settle in the original document. */
object NavigationCompletion {
    fun hasLoaded(state: Map<String, Any?>, requested: String, previous: String?): Boolean {
        if (state["readyState"] != "complete") return false
        val actual = state["url"] as? String ?: return false
        if (actual.isBlank()) return false
        if (state["sameDocument"] == false) return true
        return state["sameDocument"] == true && actual == requested && previous != null &&
            previous != requested && previous.substringBefore('#') == requested.substringBefore('#')
    }
}
