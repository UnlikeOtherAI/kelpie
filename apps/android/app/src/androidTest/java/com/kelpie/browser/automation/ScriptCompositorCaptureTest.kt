package com.kelpie.browser.automation

import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.FrameLayout
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.kelpie.browser.handlers.HandlerContext
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Window captures require the certified recording scene. */
class ScriptCompositorCaptureTest : ScriptPublicFixture() {
    @Test
    fun uncertifiedSceneRefusesBeforePixelCopy() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                load(client, server)
                val view = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                var code: String? = null
                instrumentation.runOnMainSync {
                    try {
                        ScriptCompositorCapture(view) { -1L }.rectangle()
                    } catch (error: ScriptFailure) {
                        code = error.code
                    }
                }
                assertEquals("CAPTURE_VIEW_UNAVAILABLE", code)
            }
        }
    }

    @Test
    fun exportedPageDoesNotContainTheNativeStopControl() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val script =
                    client
                        .script(tab, client.action("screenshot"))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                assertTrue(result.toString(), result.getBoolean("success"))
                val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                val file = retrieve(client, result.getString("runId"), artifact)
                val bitmap = checkNotNull(BitmapFactory.decodeFile(file.path))
                try {
                    // The entire upper strip of the fixture is white. A sampled
                    // Stop control anywhere in that strip would introduce dark pixels.
                    for (y in 0 until bitmap.height / 10 step 4) {
                        for (x in 0 until bitmap.width step 4) {
                            val pixel = bitmap.getPixel(x, y)
                            assertTrue(Color.red(pixel) > 245 && Color.green(pixel) > 245 && Color.blue(pixel) > 245)
                        }
                    }
                } finally {
                    bitmap.recycle()
                }
            }
        }
    }

    @Test
    fun uniformAncestorScaleIsCapturedAndRestored() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val view = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                val parent = view.parent as View
                var width = 0
                var mappedWidth = 0
                var originalPivotX = 0f
                var originalPivotY = 0f
                val originalLayout = view.layoutParams
                try {
                    instrumentation.runOnMainSync {
                        // Use pixel-aligned dimensions so the half-scale frame
                        // has no fractional edge that could include adjacent UI.
                        view.layoutParams = FrameLayout.LayoutParams(view.width and -2, view.height and -2)
                    }
                    ui.waitForIdle()
                    instrumentation.runOnMainSync {
                        originalPivotX = parent.pivotX
                        originalPivotY = parent.pivotY
                        parent.pivotX = 0f
                        parent.pivotY = 0f
                        parent.scaleX = 0.5f
                        parent.scaleY = 0.5f
                        width = view.width
                        mappedWidth = ScriptCompositorCapture(view) { 1L }.rectangle().width()
                    }
                    assertEquals(width / 2.0, mappedWidth.toDouble(), 1.0)
                    val script =
                        client
                            .script(tab, client.action("screenshot"))
                            .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                    val result = playRecorded(client, script)
                    assertTrue(result.toString(), result.getBoolean("success"))
                    val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                    val image = checkNotNull(BitmapFactory.decodeFile(retrieve(client, result.getString("runId"), artifact).path))
                    try {
                        var nonwhite = false
                        for (y in 0 until image.height step 5) {
                            for (x in 0 until image.width step 5) {
                                val pixel = image.getPixel(x, y)
                                if (Color.red(pixel) < 200 || Color.green(pixel) < 200 || Color.blue(pixel) < 200) nonwhite = true
                            }
                        }
                        assertTrue("Scaled export must include rendered page content", nonwhite)
                    } finally {
                        image.recycle()
                    }
                    var rejected = false
                    instrumentation.runOnMainSync {
                        parent.scaleY = 0.7f
                        try {
                            ScriptCompositorCapture(view) { 1L }.rectangle()
                        } catch (_: ScriptFailure) {
                            rejected = true
                        }
                    }
                    assertTrue("Nonuniform transform must be refused", rejected)
                } finally {
                    instrumentation.runOnMainSync {
                        parent.scaleX = 1f
                        parent.scaleY = 1f
                        parent.pivotX = originalPivotX
                        parent.pivotY = originalPivotY
                        view.layoutParams = originalLayout
                    }
                }
                assertEquals(1f, parent.scaleX, 0f)
                assertEquals(1f, parent.scaleY, 0f)
            }
        }
    }

    @Test
    fun actionModeInspectorAndPanelChangesInvalidateSceneGeneration() {
        val context = HandlerContext()
        context.scriptCaptureScene = true
        val initial = context.scriptCaptureSceneGeneration
        context.scriptCaptureActionMode = true
        val actionMode = context.scriptCaptureSceneGeneration
        context.scriptCaptureActionMode = false
        val restored = context.scriptCaptureSceneGeneration
        context.isIn3DInspector = true
        val inspector = context.scriptCaptureSceneGeneration
        context.isIn3DInspector = false
        context.requestPanel("settings")
        val panel = context.scriptCaptureSceneGeneration
        context.clearPanel()
        assertTrue(actionMode > initial)
        assertTrue(restored > actionMode)
        assertTrue(inspector > restored)
        assertTrue(panel > inspector)
        assertTrue(context.scriptCaptureSceneGeneration > panel)
        assertFalse(context.scriptCaptureActionMode)
        assertFalse(context.isIn3DInspector)
        assertEquals(null, context.activePanel.value)
    }

    @Test
    fun tabOverviewIsDismissedBeforeAnyRecordingPixelsArePublished() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                ui.onNodeWithContentDescription("More").performClick()
                ui.onNode(hasText("Tabs (", substring = true)).performClick()
                ui.waitUntil(10_000) { ui.onAllNodesWithText("Done").fetchSemanticsNodes().isNotEmpty() }
                val script =
                    client
                        .script(tab, client.action("screenshot"))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                assertTrue(result.toString(), result.getBoolean("success"))
                assertTrue(ui.onAllNodesWithText("Done").fetchSemanticsNodes().isEmpty())
                val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                assertTrue(retrieve(client, result.getString("runId"), artifact).length() > 0)
            }
        }
    }

    @Test
    fun addressEditingIsRemovedFromTheRecordingSceneAndRestoredAfterward() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                ui.onNodeWithTag("browser-address").performClick()
                ui.onNodeWithTag("browser-address").performTextInput("private-address-canary")
                val script =
                    client
                        .script(tab, client.action("screenshot"))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                assertTrue(result.toString(), result.getBoolean("success"))
                val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                val image = checkNotNull(BitmapFactory.decodeFile(retrieve(client, result.getString("runId"), artifact).path))
                try {
                    for (y in image.height * 9 / 10 until image.height step 4) {
                        for (x in 0 until image.width step 4) {
                            val pixel = image.getPixel(x, y)
                            assertTrue(Color.red(pixel) > 245 && Color.green(pixel) > 245 && Color.blue(pixel) > 245)
                        }
                    }
                } finally {
                    image.recycle()
                }
                ui.onNodeWithTag("browser-address").assertExists()
            }
        }
    }

    @Test
    fun nativeActionModeRefusesCaptureAndClosingItRestoresCapture() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                lateinit var mode: ActionMode
                instrumentation.runOnMainSync {
                    mode =
                        checkNotNull(
                            ui.activity.startActionMode(
                                object : ActionMode.Callback {
                                    override fun onCreateActionMode(
                                        mode: ActionMode,
                                        menu: Menu,
                                    ): Boolean {
                                        menu.add("Scene obstruction")
                                        return true
                                    }

                                    override fun onPrepareActionMode(
                                        mode: ActionMode,
                                        menu: Menu,
                                    ): Boolean = false

                                    override fun onActionItemClicked(
                                        mode: ActionMode,
                                        item: MenuItem,
                                    ): Boolean = false

                                    override fun onDestroyActionMode(mode: ActionMode) = Unit
                                },
                            ),
                        )
                }
                val script =
                    client
                        .script(tab, client.action("screenshot"))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                try {
                    val refused = playRecorded(client, script)
                    assertFalse(refused.getBoolean("success"))
                    assertEquals("CAPTURE_VIEW_UNAVAILABLE", refused.getJSONObject("error").getString("code"))
                    assertEquals(0, refused.getJSONArray("artifacts").length())
                } finally {
                    instrumentation.runOnMainSync { mode.finish() }
                }
                ui.waitForIdle()
                val recovered = playRecorded(client, script)
                assertTrue(recovered.toString(), recovered.getBoolean("success"))
                val artifact = recovered.getJSONArray("artifacts").getJSONObject(0)
                assertTrue(retrieve(client, recovered.getString("runId"), artifact).length() > 0)
            }
        }
    }
}
