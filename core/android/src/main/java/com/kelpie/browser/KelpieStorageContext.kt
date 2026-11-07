package com.kelpie.browser

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import java.io.File

/** Keeps browser files and preferences separate from the containing app's state. */
class KelpieStorageContext(base: Context) : ContextWrapper(base) {
    override fun getApplicationContext(): Context = KelpieEnvironment.app

    override fun getFilesDir(): File = File(baseContext.filesDir, "kelpie-browser").apply { mkdirs() }

    override fun getCacheDir(): File = File(baseContext.cacheDir, "kelpie-browser").apply { mkdirs() }

    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        baseContext.getSharedPreferences("kelpie.browser.$name", mode)
}
