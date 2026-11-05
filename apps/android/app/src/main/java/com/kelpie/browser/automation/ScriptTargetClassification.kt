package com.kelpie.browser.automation

/** Per-evaluation provenance; cancellation is not itself evidence of sensitivity. */
class ScriptTargetClassification {
    @Volatile private var evaluationStarted = false

    @Volatile private var explicitClassification = false

    fun started() {
        evaluationStarted = true
    }

    fun received(
        sensitive: Boolean?,
        sensitivityKnown: Boolean?,
    ) {
        explicitClassification = sensitive == true || (sensitive == false && sensitivityKnown == true)
    }

    fun unknown(): Boolean = evaluationStarted && !explicitClassification
}
