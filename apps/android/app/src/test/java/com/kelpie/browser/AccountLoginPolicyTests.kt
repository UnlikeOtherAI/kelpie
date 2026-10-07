package com.kelpie.browser

import com.kelpie.browser.account.AccountLoginPolicy
import com.kelpie.browser.account.AccountLoginPolicy.Outcome
import com.kelpie.browser.account.UOAAuthorization
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountLoginPolicyTests {
    @Test fun onlyTheExactAuthorizeEndpointOpensInTheLoginView() {
        assertTrue(AccountLoginPolicy.isAuthorizeUrl(UOAAuthorization().url("client")))
        listOf(
            "http://authentication.unlikeotherai.com/oauth/authorize?x=1",
            "https://authentication.unlikeotherai.com.evil.example/oauth/authorize",
            "https://evil.example@authentication.unlikeotherai.com/oauth/authorize",
            "https://authentication.unlikeotherai.com:8443/oauth/authorize",
            "https://authentication.unlikeotherai.com/oauth/token",
            "https://accounts.google.com/o/oauth2/auth",
            "not a url",
        ).forEach { assertFalse(it, AccountLoginPolicy.isAuthorizeUrl(it)) }
    }

    @Test fun callbackInterceptionIsExact() {
        assertTrue(AccountLoginPolicy.isCallback("com.unlikeotherai.kelpie", "oauth", "/callback"))
        assertFalse(AccountLoginPolicy.isCallback("https", "oauth", "/callback"))
        assertFalse(AccountLoginPolicy.isCallback("com.unlikeotherai.kelpie", "oauth.example", "/callback"))
        assertFalse(AccountLoginPolicy.isCallback("com.unlikeotherai.kelpie", "oauth", "/callback/extra"))
        assertFalse(AccountLoginPolicy.isCallback(null, null, null))
    }

    @Test fun navigationStaysHttpsOnly() {
        assertTrue(AccountLoginPolicy.allowsNavigation("https"))
        listOf("http", "intent", "javascript", "file", "content", "market", null).forEach {
            assertFalse("$it", AccountLoginPolicy.allowsNavigation(it))
        }
    }

    @Test fun inAppLoginFallsBackToTheBrowserOnlyWithoutAWebView() {
        val callback = "${UOAAuthorization.CALLBACK}?state=s&code=c"
        assertEquals(Outcome.Callback(callback), AccountLoginPolicy.outcome(-1, callback))
        assertEquals(Outcome.WebViewUnavailable, AccountLoginPolicy.outcome(AccountLoginPolicy.RESULT_WEBVIEW_UNAVAILABLE, null))
        assertEquals(Outcome.Cancelled, AccountLoginPolicy.outcome(0, null))
        assertEquals(Outcome.Cancelled, AccountLoginPolicy.outcome(0, callback))
        assertEquals(Outcome.Cancelled, AccountLoginPolicy.outcome(-1, null))
    }
}
