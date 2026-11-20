package com.kelpie.browser

import android.app.Application
import android.content.pm.PackageInstaller
import android.os.Build

class KelpieApp : Application() {
    var updates: AppUpdates? = null
        private set

    override fun onCreate() {
        super.onCreate()
        KelpieEnvironment.initialize(this)
        if (!isStoreInstall()) {
            updates = AppUpdates(this)
        }
    }

    @Suppress("DEPRECATION")
    private fun isStoreInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return packageManager.getInstallerPackageName(packageName) == PLAY_STORE
        }
        val source = packageManager.getInstallSourceInfo(packageName)
        if (source.installingPackageName == PLAY_STORE || source.initiatingPackageName == PLAY_STORE) {
            return true
        }
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            source.packageSource == PackageInstaller.PACKAGE_SOURCE_STORE
    }

    private companion object {
        const val PLAY_STORE = "com.android.vending"
    }
}
