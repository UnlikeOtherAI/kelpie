package com.kelpie.browser

import android.app.Application

class KelpieApp : Application() {
    lateinit var updates: AppUpdates
        private set

    override fun onCreate() {
        super.onCreate()
        KelpieEnvironment.initialize(this)
        updates = AppUpdates(this)
    }
}
