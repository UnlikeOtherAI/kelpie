package com.kelpie.browser.network

/**
 * Process-scoped hand-off between MainActivity (which builds the HTTPServer and
 * MDNSAdvertiser instances) and KelpieNetworkService (which owns their
 * lifecycle while the app is in the foreground).
 *
 * This is intentionally not a static reference to an Activity — both fields
 * hold network-layer objects that are already Application-scoped (see the
 * HTTPServer and MDNSAdvertiser docs). MainActivity must call `clear()` from
 * its `onDestroy` so a recreated Activity cannot pick up dangling state.
 */
data class NetworkServiceStage(
    val httpServer: HTTPServer,
    val mdnsAdvertiser: MDNSAdvertiser,
)

object NetworkServiceState {
    @Volatile
    private var stage: NetworkServiceStage? = null

    fun stage(stage: NetworkServiceStage) {
        this.stage = stage
    }

    fun snapshot(): NetworkServiceStage? = stage

    fun clear() {
        stage = null
    }
}
