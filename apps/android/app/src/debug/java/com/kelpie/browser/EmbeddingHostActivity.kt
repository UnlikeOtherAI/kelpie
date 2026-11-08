package com.kelpie.browser

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import com.kelpie.browser.account.KelpieUOAIdentity
import com.kelpie.browser.account.KelpieUOASession
import com.kelpie.browser.account.UOATransport
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.Request

/** Debug-only host: opens the SDK after Activity startup and moves its complete view. */
class EmbeddingHostActivity : ComponentActivity() {
    private var browser: KelpieBrowserSession? = null
    private lateinit var first: FrameLayout
    private lateinit var second: FrameLayout
    private lateinit var status: TextView
    private var useSecond = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val controls = LinearLayout(this)
        status = TextView(this).apply { text = "Host ready; browser not created." }

        fun button(
            label: String,
            action: () -> Unit,
        ) {
            controls.addView(
                Button(this).apply {
                    text = label
                    setOnClickListener { action() }
                },
            )
        }
        button("Open browser") {
            if (browser == null) {
                browser = KelpieBrowserSession(this, localControlEnabled = false, uoaSession = HostSession())
            }
            browser?.attachTo(if (useSecond) second else first)
            status.text = "Browser opened after Activity startup."
        }
        button("Move browser") {
            useSecond = !useSecond
            browser?.attachTo(if (useSecond) second else first)
            status.text = if (useSecond) "Browser moved to second container." else "Browser moved back."
        }
        button("Close browser") {
            browser?.close()
            browser = null
            status.text = "Browser closed; host still running."
        }
        val panes = LinearLayout(this)
        first = FrameLayout(this).apply { id = View.generateViewId() }
        second = FrameLayout(this).apply { id = View.generateViewId() }
        panes.addView(first, LinearLayout.LayoutParams(0, -1, 1f))
        panes.addView(second, LinearLayout.LayoutParams(0, -1, 1f))
        layout.addView(controls)
        layout.addView(status)
        layout.addView(panes, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(layout)
    }

    private inner class HostSession : KelpieUOASession {
        override val identity = MutableStateFlow(KelpieUOAIdentity(null, null))

        override suspend fun request(
            path: String,
            method: String,
            body: String?,
            version: String?,
        ): UOATransport.Response = throw UOATransport.Failure(401)

        override suspend fun settingsRequest(): Request = throw UOATransport.Failure(401)

        override fun signIn() {
            status.text = "Sign-in delegated to host UOA session."
        }

        override fun signOut() {
            status.text = "Sign-out delegated to host UOA session."
        }
    }
}
