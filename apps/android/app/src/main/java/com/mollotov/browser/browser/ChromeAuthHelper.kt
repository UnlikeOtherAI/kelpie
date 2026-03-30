package com.mollotov.browser.browser

import android.app.Activity
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebView
import androidx.browser.customtabs.CustomTabsIntent

/**
 * Opens a URL in Chrome Custom Tabs (which share Chrome's saved passwords and cookies),
 * then syncs cookies back into the WebView when the user returns.
 */
class ChromeAuthHelper {

    fun authenticate(url: String, webView: WebView, activity: Activity) {
        // Open in Chrome Custom Tabs — shares Chrome's cookies and saved passwords
        val intent = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
        intent.launchUrl(activity, Uri.parse(url))

        // When the user returns to our app (via back), sync cookies and reload.
        // Chrome Custom Tabs shares cookies via the system CookieManager automatically,
        // so after the user authenticates in Chrome, the WebView CookieManager
        // already has the cookies. We just need to flush and reload.
        CookieManager.getInstance().flush()
        webView.reload()
    }

    /**
     * Called when the activity resumes after Chrome Custom Tabs — sync cookies and reload.
     */
    fun onResume(webView: WebView?) {
        webView ?: return
        CookieManager.getInstance().flush()
        webView.reload()
    }
}
