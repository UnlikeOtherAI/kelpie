package com.kelpie.browser

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.widget.TextView
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject

/** Separate non-shipping app. No installer or browser profile can be reached. */
class UpdateVerificationActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(
            TextView(this).apply {
                text = "Kelpie Update Verification\nUpdate is simulated. No real installation changes."
                setPadding(32, 48, 32, 32)
            },
        )
    }

    override fun onResume() {
        super.onResume()
        if (updates == null) {
            val server = MockWebServer()
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        val item =
                            JSONObject()
                                .put("target", "android")
                                .put("version", "0.2.3")
                                .put("url", "https://play.google.com/store/apps/details?id=com.kelpie.browser")
                        val entry =
                            JSONObject()
                                .put("draft", false)
                                .put("prerelease", false)
                                .put("body", "<!-- kelpie-update: $item -->")
                        return MockResponse().setBody(JSONArray().put(entry).toString())
                    }
                }
            // Start off the UI thread; MockWebServer.url() otherwise starts synchronously.
            Thread {
                server.start()
                val endpoint = server.url("/releases").toString()
                runOnUiThread {
                    updates =
                        AppUpdates(applicationContext, endpoint) {
                            AlertDialog
                                .Builder(this)
                                .setTitle("Simulated update completed")
                                .setMessage("No installer ran and no Kelpie installation changed.")
                                .setPositiveButton("OK", null)
                                .show()
                        }
                    updates?.attach(this)
                }
            }.start()
        } else {
            updates?.attach(this)
        }
    }

    override fun onPause() {
        updates?.detach(this)
        super.onPause()
    }

    companion object {
        private var updates: AppUpdates? = null
    }
}
