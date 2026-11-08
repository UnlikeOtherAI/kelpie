package com.kelpie.browser

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import java.io.File

/** Keeps browser files and preferences separate from the containing app's state. */
class KelpieStorageContext(
    base: Context,
) : ContextWrapper(base) {
    override fun getApplicationContext(): Context = KelpieEnvironment.app

    override fun getFilesDir(): File = File(baseContext.filesDir, "kelpie-browser").apply { mkdirs() }

    override fun getCacheDir(): File = File(baseContext.cacheDir, "kelpie-browser").apply { mkdirs() }

    override fun getExternalFilesDir(type: String?): File? = baseContext.getExternalFilesDir(type)?.let { File(it, "kelpie-browser").apply { mkdirs() } }

    override fun getExternalCacheDir(): File? = baseContext.externalCacheDir?.let { File(it, "kelpie-browser").apply { mkdirs() } }

    override fun getNoBackupFilesDir(): File = File(baseContext.noBackupFilesDir, "kelpie-browser").apply { mkdirs() }

    override fun getSharedPreferences(
        name: String,
        mode: Int,
    ): SharedPreferences = baseContext.getSharedPreferences("kelpie.browser.$name", mode)
}

internal fun Context.kelpieActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.kelpieActivity()
        else -> null
    }
