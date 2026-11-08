package com.kelpie.browser

import android.app.Application

class KelpieApp : Application() {
    override fun onCreate() {
        super.onCreate()
        KelpieEnvironment.initialize(this)
    }
}
