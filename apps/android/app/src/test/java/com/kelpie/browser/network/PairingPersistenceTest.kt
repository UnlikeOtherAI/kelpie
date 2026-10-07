package com.kelpie.browser.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * "Always allow" must survive an app restart and later approvals: the next
 * store instance reads the same file and still accepts the issued bearer.
 */
class PairingPersistenceTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun approveAlways(
        store: PairingStore,
        clientId: String,
        source: String,
    ): String {
        val request = store.startPairing(clientId, clientId, source).request
        assertNotNull(request)
        return store.approve(request!!.requestId, persist = true)!!.first
    }

    @Test
    fun alwaysAllowSurvivesRestartAndLaterApprovals() {
        val file = folder.root.resolve("pairings.json")
        val first = PairingStore(file)
        val minis = approveAlways(first, "minis", "192.168.1.215")
        // A second approval replaces the existing file rather than appending.
        val umac = approveAlways(first, "umac", "192.168.1.192")

        val restarted = PairingStore(file)
        assertEquals("minis", restarted.validateBearer(minis))
        assertEquals("umac", restarted.validateBearer(umac))
        assertEquals(2, restarted.listPersistent().size)
    }
}
