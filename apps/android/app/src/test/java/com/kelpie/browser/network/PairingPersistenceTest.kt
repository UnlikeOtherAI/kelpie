package com.kelpie.browser.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Model approvals survive store replacement and are independent of client tokens.
 */
class PairingPersistenceTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun hashComparisonRetainsEveryDifference() {
        // XOR-accumulating these byte differences cancels them to zero.
        assertFalse(PairingStore.constantTimeEqualsHex("0011", "1100"))
        assertFalse(PairingStore.constantTimeEqualsHex("a".repeat(64), "b".repeat(64)))
        assertFalse(PairingStore.constantTimeEqualsHex("00", "0000"))
        assertTrue(PairingStore.constantTimeEqualsHex("ab01".repeat(16), "ab01".repeat(16)))
    }

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
        val first = testPairingStore(file)
        approveAlways(first, "minis", "192.168.1.215")
        // A second computer preserves the first computer's permission.
        approveAlways(first, "umac", "192.168.1.192")

        val restarted = testPairingStore(file)
        assertEquals("host:192.168.1.215", restarted.trustedComputers.clientId("192.168.1.215"))
        assertEquals("host:192.168.1.192", restarted.trustedComputers.clientId("192.168.1.192"))
        assertEquals(2, restarted.trustedComputers.list().size)
    }
}
