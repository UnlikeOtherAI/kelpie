package com.kelpie.browser

class MainActivity : KelpieBrowserActivity() {
    private val updates get() = (application as KelpieApp).updates

    override fun onResume() {
        super.onResume()
        updates.attach(this)
    }

    override fun onPause() {
        updates.detach(this)
        super.onPause()
    }
}
