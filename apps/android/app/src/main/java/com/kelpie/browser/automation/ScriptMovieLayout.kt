package com.kelpie.browser.automation

/** Only continuous movie capture changes the native viewport layout. */
internal fun scriptUsesMovieLayout(capture: Map<String, Any?>): Boolean = (capture["formats"] as? List<*>).orEmpty().any { it == "gif" || it == "video" }
