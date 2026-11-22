package com.kelpie.browser.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.ContentUris
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.core.view.children
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.MainActivity
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class DownloadsFlowTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    fun attachmentOpensSharesAndSurvivesClear() {
        val filename = "receipt-${UUID.randomUUID()}.txt"
        val server = MockWebServer()
        server.dispatcher =
            object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse =
                    when (request.path) {
                        "/" -> MockResponse().addHeader("Content-Type", "text/html").setBody("<a id='save' href='/file'>Save receipt</a>")
                        "/file" ->
                            MockResponse()
                                .addHeader("Content-Type", "application/octet-stream")
                                .addHeader("Content-Disposition", "attachment; filename=\"$filename\"")
                                .setBody("Saved receipt")
                        else -> MockResponse().setResponseCode(404)
                    }
            }
        server.use {
            server.start()
            ui.onNodeWithContentDescription("Downloads").assertDoesNotExist()
            val page = ui.runOnIdle { requireNotNull(webView(ui.activity.window.decorView)) }
            val pageUrl = server.url("/").toString()
            ui.runOnIdle { page.loadUrl(pageUrl) }
            ui.waitUntil(15000) {
                val result = CountDownLatch(1)
                var ready = false
                ui.runOnUiThread {
                    page.evaluateJavascript("!!document.getElementById('save')") { value ->
                        ready = value == "true"
                        result.countDown()
                    }
                }
                result.await(2, TimeUnit.SECONDS) && ready
            }
            ui.runOnIdle { page.evaluateJavascript("document.getElementById('save').click()", null) }
            ui.waitUntil(15000) { ui.onAllNodesWithContentDescription("Downloads").fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithContentDescription("Downloads").performClick()
            ui.waitUntil(15000) { ui.onAllNodesWithContentDescription("Share downloaded file").fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText(filename).assertIsDisplayed()
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val filter =
                IntentFilter(Intent.ACTION_VIEW).apply {
                    addDataScheme("content")
                    addDataType("text/plain")
                }
            for ((intent, click) in listOf(
                filter to { ui.onNodeWithText(filename).performClick() },
                IntentFilter(Intent.ACTION_CHOOSER) to { ui.onNodeWithContentDescription("Share downloaded file").performClick() },
            )) {
                val monitor = instrumentation.addMonitor(intent, Instrumentation.ActivityResult(Activity.RESULT_OK, null), true)
                try {
                    click()
                    assertEquals(1, monitor.hits)
                } finally {
                    instrumentation.removeMonitor(monitor)
                }
            }
            ui.onNodeWithText("Clear").performClick()
            ui.onNodeWithText("No downloads").assertIsDisplayed()
            ui.onNodeWithText("Done").performClick()
            ui.onNodeWithContentDescription("Downloads").assertDoesNotExist()
            val resolver = ui.activity.contentResolver
            val downloads = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val idColumn = MediaStore.Downloads._ID
            val uri =
                requireNotNull(resolver.query(downloads, arrayOf(idColumn), "${MediaStore.Downloads.DISPLAY_NAME} = ?", arrayOf(filename), null)).use {
                    check(it.moveToFirst())
                    ContentUris.withAppendedId(downloads, it.getLong(0))
                }
            try {
                assertEquals("Saved receipt", resolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() })
            } finally {
                resolver.delete(uri, null, null)
            }
        }
    }

    private fun webView(view: View): WebView? =
        when (view) {
            is WebView -> view
            is ViewGroup -> view.children.firstNotNullOfOrNull(::webView)
            else -> null
        }
}
