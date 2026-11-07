package com.kelpie.browser.network

/**
 * Process-scoped hand-off between MainActivity (which builds the HTTPServer and
 * MDNSAdvertiser instances) and KelpieNetworkService (which owns their
 * foreground lifetime).
 *
 * This is intentionally not a static reference to an Activity — both fields
 * hold network-layer objects that are already Application-scoped (see the
 * HTTPServer and MDNSAdvertiser docs). Each owner stops its exact stage; clearing
 * an old stage must never clear a replacement Activity's stage.
 */
data class NetworkServiceStage(
    val httpServer: HTTPServer,
    val mdnsAdvertiser: MDNSAdvertiser,
) {
    fun stop() {
        try {
            mdnsAdvertiser.shutdown()
        } catch (error: Exception) {
            android.util.Log.w("KelpieNetworkService", "mDNS shutdown failed", error)
        }
        try {
            httpServer.stop()
        } catch (error: Exception) {
            android.util.Log.w("KelpieNetworkService", "HTTP server shutdown failed", error)
        }
    }
}

object NetworkServiceState {
    @Volatile
    private var stage: NetworkServiceStage? = null

    @Synchronized fun stage(stage: NetworkServiceStage) {
        this.stage = stage
    }

    fun snapshot(): NetworkServiceStage? = stage

    @Synchronized fun clearIf(expected: NetworkServiceStage) {
        if (stage === expected) stage = null
    }
}
