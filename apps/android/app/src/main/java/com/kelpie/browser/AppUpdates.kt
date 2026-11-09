package com.kelpie.browser

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.unlikeotherai.kelpie.app.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.lang.ref.WeakReference
import java.util.concurrent.TimeUnit

/** One process/session: recreating an Activity must not undo Not now. */
class AppUpdates(
    context: Context,
    private val feedURL: String = "https://api.github.com/repos/UnlikeOtherAI/kelpie/releases?per_page=100",
    private val performUpdate: (() -> Unit)? = null,
) {
    private val preferences = context.getSharedPreferences("app-updates", Context.MODE_PRIVATE)
    private val dismissed = mutableSetOf<String>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build()
    private var activity = WeakReference<Activity>(null)
    private var started = false
    private var candidate: AppRelease? = null
    private var dialog: AlertDialog? = null

    fun attach(owner: Activity) {
        activity = WeakReference(owner)
        present()
        if (started) return
        started = true
        scope.launch {
            while (true) {
                val success = check()
                delay(if (success) 6 * 60 * 60 * 1000L else 15 * 60 * 1000L)
            }
        }
    }

    fun detach(owner: Activity) {
        if (activity.get() !== owner) return
        activity.clear()
        // Do not lose a prompt merely because the app was backgrounded before a choice.
        dialog?.setOnDismissListener(null)
        dialog?.dismiss()
        dialog = null
    }

    private suspend fun check(): Boolean {
        val result =
            withContext(Dispatchers.IO) {
                runCatching {
                    val request =
                        Request
                            .Builder()
                            .url(feedURL)
                            .header("Accept", "application/vnd.github+json")
                            .header("User-Agent", "Kelpie-update-check")
                            .build()
                    client.newCall(request).execute().use { response ->
                        check(response.code == 200)
                        val source = checkNotNull(response.body).source()
                        source.request(8 * 1024 * 1024L + 1)
                        check(source.buffer.size <= 8 * 1024 * 1024L)
                        val body = source.readUtf8()
                        ReleaseFeed.newest(JSONArray(body), BuildConfig.VERSION_NAME)
                    }
                }
            }
        if (result.isFailure) return false
        candidate = result.getOrNull()
        present()
        return true
    }

    private fun dismiss(item: AppRelease) {
        dismissed.add(item.version)
        dialog = null
    }

    private fun present() {
        val owner = activity.get() ?: return
        val item = candidate ?: return
        if (owner.isFinishing ||
            owner.isDestroyed ||
            dialog != null ||
            item.version in dismissed ||
            item.version in preferences.getStringSet("skippedVersions", emptySet()).orEmpty()
        ) {
            return
        }
        dialog =
            AlertDialog
                .Builder(owner)
                .setTitle("A new Kelpie version is available")
                .setMessage("Kelpie ${item.version} is available. Not now asks again next time you start the app.")
                .setPositiveButton("Update") { _, _ ->
                    dismiss(item)
                    runCatching {
                        val action = performUpdate
                        if (action != null) action() else owner.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(item.url)))
                    }.onFailure { showError(owner, "The update page could not open. Try again after restarting Kelpie.") }
                }.setNegativeButton("Skip version") { _, _ ->
                    val skipped = preferences.getStringSet("skippedVersions", emptySet()).orEmpty() + item.version
                    if (!preferences.edit().putStringSet("skippedVersions", skipped).commit()) {
                        showError(owner, "Kelpie could not save Skip version. Please try again after restarting the app.")
                    }
                    dismiss(item)
                }.setNeutralButton("Not now") { _, _ -> dismiss(item) }
                .setOnCancelListener { dismiss(item) }
                .create()
        dialog?.show()
    }

    private fun showError(
        owner: Activity,
        message: String,
    ) {
        AlertDialog
            .Builder(owner)
            .setTitle("Kelpie could not update")
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }
}
