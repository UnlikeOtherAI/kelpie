package com.kelpie.browser.handlers

internal suspend fun HandlerContext.enter3DInspector() {
    val snapshot = runCatching { captureScreenshotPayload(resolution = ScreenshotResolution.VIEWPORT) }.getOrNull()
    evaluateJS(Snapshot3DBridge.ENTER_SCRIPT)
    val image = snapshot?.get("image") as? String
    if (image != null) runCatching { evaluateJS(Snapshot3DBridge.previewScript(image)) }
}
