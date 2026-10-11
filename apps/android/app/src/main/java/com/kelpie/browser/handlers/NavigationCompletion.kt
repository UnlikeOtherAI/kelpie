package com.kelpie.browser.handlers

/** Completion requires a replacement document; its final URL may be a redirect. */
object NavigationCompletion {
    fun hasLoaded(state: Map<String, Any?>): Boolean =
        state["sameDocument"] == false && state["readyState"] == "complete" &&
            !(state["url"] as? String).isNullOrBlank()
}
