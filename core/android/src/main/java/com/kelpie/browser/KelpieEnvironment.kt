package com.kelpie.browser

import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.browser.NetworkTrafficStore
import com.kelpie.browser.ui.TabletViewportPresetStore

object KelpieEnvironment {
    lateinit var app: Context
        private set

    var profileID: String = "signed-out"
        private set
    private var profileSubject: String? = null

    /** Selects local files before creating this process's browser; it grants no account or agent authority. */
    fun configureProfile(
        issuer: String,
        subject: String,
    ) {
        check(!::app.isInitialized) { "A browser process cannot switch its private profile" }
        require(issuer.startsWith("https://") && subject.isNotEmpty())
        val value =
            org.json
                .JSONArray(listOf(issuer, subject))
                .toString()
                .toByteArray(Charsets.UTF_8)
        profileID =
            java.security.MessageDigest
                .getInstance("SHA-256")
                .digest(value)
                .joinToString("") { "%02x".format(it) }
        profileSubject = subject
    }

    internal fun requireProfile(subject: String?) {
        require(profileSubject == subject) { "Verify and configure the host's browser profile first" }
    }

    fun standalone(context: Context): Boolean = context.packageName in setOf("com.kelpie.browser", "com.kelpie.browser.nessieverify")

    fun context(context: Context): Context = if (standalone(context)) context else KelpieStorageContext(context)

    fun initialize(context: Context) {
        if (::app.isInitialized) return
        app = if (standalone(context)) context.applicationContext else KelpieStorageContext(context.applicationContext)
        com.kelpie.browser.browser.PartitionRegistry
            .initialize(app)
        // Embedded browsing leaves the containing app's process-wide debug policy intact.
        if (standalone(context)) WebView.setWebContentsDebuggingEnabled(true)
        NetworkTrafficStore.init(app)
        TabletViewportPresetStore.init(app)
        AIState.initialize(app)
    }
}
