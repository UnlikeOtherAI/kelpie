package com.kelpie.browser.ai.openai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthEvaluatorTest {
    private val models = listOf(DiscoveredModel("m1", status = ModelStatus.LOADED), DiscoveredModel("m2", status = ModelStatus.LOADING))
    private val discovered = ProbeOutcome.Discovered(models, 12)
    private val unreachable = ProbeOutcome.Failed(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "refused")

    private fun eval(
        previous: EndpointHealth?,
        outcome: ProbeOutcome,
        model: String? = "m1",
        now: Long = 1_000,
    ) = HealthEvaluator.evaluate(previous, outcome, model, now)

    @Test
    fun aTwoHundredAloneIsNotReady() {
        assertEquals(HealthState.NO_MODEL, eval(null, discovered, model = null).state)
        assertEquals(HealthState.MODEL_MISSING, eval(null, discovered, model = "nope").state)
        assertEquals(false, eval(null, discovered, model = "nope").modelListed)
        assertEquals(HealthState.READY, eval(null, discovered).state)
    }

    @Test
    fun reachableButLoading() {
        val loadingModel = eval(null, discovered, model = "m2")
        assertEquals(HealthState.LOADING, loadingModel.state)
        assertTrue(loadingModel.state.online)
        assertEquals(ModelStatus.LOADING, loadingModel.modelStatus)
        val serverLoading = eval(null, ProbeOutcome.Failed(OpenAIErrorCode.ENDPOINT_LOADING, "Loading model", 503))
        assertEquals(HealthState.LOADING, serverLoading.state)
    }

    @Test
    fun authAndUnreachableAreOffline() {
        val auth = eval(null, ProbeOutcome.Failed(OpenAIErrorCode.ENDPOINT_AUTH_FAILED, "no", 401))
        assertEquals(HealthState.AUTH_FAILED, auth.state)
        assertFalse(auth.state.online)
        assertEquals(HealthState.UNREACHABLE, eval(null, unreachable).state)
        assertEquals(HealthState.UNREACHABLE, eval(null, ProbeOutcome.Failed(OpenAIErrorCode.ENDPOINT_TIMEOUT, "slow")).state)
    }

    @Test
    fun busyStaysOnline() {
        val busy = eval(null, ProbeOutcome.Failed(OpenAIErrorCode.ENDPOINT_ERROR, "rate", 429))
        assertEquals(HealthState.BUSY, busy.state)
        assertTrue(busy.state.online)
        val ready = eval(null, discovered)
        assertEquals(HealthState.BUSY, ready.effectiveState(1_500, inFlight = 1))
        assertEquals(true, ready.toPublic(1_500, 1)["online"])
        assertEquals(HealthState.READY, ready.effectiveState(1_500, inFlight = 0))
    }

    @Test
    fun onlineOfflineOnlineResetsGenerationVerification() {
        val unsupported = ProbeOutcome.DiscoveryUnsupported(5)
        val first = eval(null, unsupported)
        assertEquals(HealthState.MODEL_MISSING, first.state)
        val verified = HealthEvaluator.recordGeneration(first, "m1", 2_000)
        assertEquals(HealthState.READY, verified.state)
        assertEquals(2_000L, verified.generationVerifiedAtMs)
        val stillReady = eval(verified, unsupported, now = 3_000)
        assertEquals(HealthState.READY, stillReady.state)
        assertEquals(2_000L, stillReady.generationVerifiedAtMs)
        val offline = eval(stillReady, unreachable, now = 4_000)
        assertEquals(HealthState.UNREACHABLE, offline.state)
        assertNull(offline.generationVerifiedAtMs)
        val back = eval(offline, unsupported, now = 5_000)
        assertEquals(HealthState.MODEL_MISSING, back.state)
        assertNull(back.generationVerifiedAtMs)
        val discoveredAgain = eval(offline, discovered, now = 6_000)
        assertEquals(HealthState.READY, discoveredAgain.state)
    }

    @Test
    fun staleResultsReadAsUnknown() {
        val ready = eval(null, discovered, now = 10_000)
        val public = ready.toPublic(10_000 + EndpointHealth.STALE_AFTER_MS + 1, 0)
        assertEquals("unknown", public["state"])
        assertEquals(true, public["stale"])
        assertEquals(false, public["online"])
        val fresh = ready.toPublic(10_000 + EndpointHealth.STALE_AFTER_MS, 0)
        assertEquals("ready", fresh["state"])
        assertEquals(false, fresh["stale"])
        assertNotNull(fresh["checkedAt"])
        val never = EndpointHealth().toPublic(0, 0)
        assertEquals("unknown", never["state"])
        assertEquals(true, never["stale"])
    }

    @Test
    fun pollingSchedule() {
        assertEquals(30_000L, HealthPollSchedule.nextDelayMs(HealthState.READY, 0))
        assertEquals(30_000L, HealthPollSchedule.nextDelayMs(HealthState.BUSY, 0))
        val backoff = (1..7).map { HealthPollSchedule.nextDelayMs(HealthState.UNREACHABLE, it) }
        assertEquals(listOf(5_000L, 10_000L, 20_000L, 40_000L, 60_000L, 60_000L, 60_000L), backoff)
        assertEquals(5_000L, HealthPollSchedule.nextDelayMs(HealthState.LOADING, 1))
    }
}
