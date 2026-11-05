package com.kelpie.browser.automation

/** Acknowledged final input can outlive its document; unknown privacy cannot expose capture. */
internal fun checkPacedPostMutation(
    result: Map<String, Any?>,
    finalStep: Boolean,
    captures: Boolean,
    protectUnknown: () -> Unit,
) {
    if (result["sensitive"] == true && captures) throw ScriptFailure("SENSITIVE_CAPTURE_REFUSED", true)
    if (result["ok"] != true || (result["sensitive"] != true && !(result["sensitive"] == false && result["sensitivityKnown"] == true))) {
        protectUnknown()
        if (!finalStep || captures) throw ScriptFailure("INPUT_UNCERTAIN", true)
    }
}
