package com.kelpie.browser.ai.openai

/** Existing inference admission only. Schemas and descriptions belong to the shared native registry. */
object AgentBrowserPolicy {
    private val observations =
        setOf(
            "get-current-url",
            "get-page-text",
            "get-visible-elements",
            "find-element",
            "get-form-state",
            "get-accessibility-tree",
            "wait-for-element",
        )
    private val actions = setOf("click", "fill", "select-option", "check", "uncheck")

    fun methods(allowActions: Boolean): Set<String> = observations + if (allowActions) actions else emptySet()
}
