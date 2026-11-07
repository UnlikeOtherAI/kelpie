package com.kelpie.browser.account

import java.net.URI

/** Pure decisions for the in-app UOA login, kept free of Android types so they are unit-testable. */
internal object AccountLoginPolicy {
    const val LOGIN_HOST = "authentication.unlikeotherai.com"

    /** Activity result code reported when no WebView could be created (e.g. provider missing). */
    const val RESULT_WEBVIEW_UNAVAILABLE = 1 // Activity.RESULT_FIRST_USER

    private const val RESULT_OK = -1 // Activity.RESULT_OK
    private const val CALLBACK_SCHEME = "com.unlikeotherai.kelpie"

    sealed interface Outcome {
        data class Callback(
            val url: String,
        ) : Outcome

        data object Cancelled : Outcome

        /** The in-app login could not run; the default browser is the only remaining route. */
        data object WebViewUnavailable : Outcome
    }

    /** The login Activity only ever opens UOA's exact authorize endpoint over https. */
    fun isAuthorizeUrl(url: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        return uri.scheme == "https" &&
            uri.host == LOGIN_HOST &&
            uri.path == "/oauth/authorize" &&
            uri.userInfo == null &&
            uri.port == -1
    }

    /** Exact match for the registered redirect URI; query validation happens in [UOAAuthorization]. */
    fun isCallback(
        scheme: String?,
        host: String?,
        path: String?,
    ): Boolean = scheme == CALLBACK_SCHEME && host == "oauth" && path == "/callback"

    /** Every other navigation stays in the login view only over https (Google handoffs included). */
    fun allowsNavigation(scheme: String?): Boolean = scheme == "https"

    fun outcome(
        resultCode: Int,
        callback: String?,
    ): Outcome =
        when {
            resultCode == RESULT_WEBVIEW_UNAVAILABLE -> Outcome.WebViewUnavailable
            resultCode == RESULT_OK && callback != null -> Outcome.Callback(callback)
            else -> Outcome.Cancelled
        }
}
