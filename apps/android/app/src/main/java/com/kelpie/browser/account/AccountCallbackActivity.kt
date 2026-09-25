package com.kelpie.browser.account

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Receives an exact public OAuth callback without creating another browser activity. */
class AccountCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent.dataString?.let(UOAAccount::receiveCallback)
        startActivity(Intent(this, com.kelpie.browser.MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
