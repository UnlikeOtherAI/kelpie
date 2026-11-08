package com.kelpie.browser.connect

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectNavigationLeaseTest {
    @Test
    fun ownNavigationReturnsTheNewDocumentOnlyAfterItSettles() {
        val lease = ConnectNavigationLease("old", "https://example.com")
        assertTrue(lease.arm("old", true))
        assertFalse(lease.allowsRead("old", false, true))
        lease.started("old", "new", "https://example.com/")
        assertFalse(lease.allowsRead("new", true, true))
        assertTrue(lease.allowsRead("new", false, true))
        assertFalse(lease.allowsRead("old", false, true))
        assertFalse(lease.allowsRead("new", false, false)) // cancelled, expired, account changed or different active tab
    }

    @Test
    fun unownedNavigationAndLaterDocumentsCannotBorrowTheLease() {
        val lease = ConnectNavigationLease("old", "https://example.com")
        assertFalse(lease.arm("old", false))
        assertTrue(lease.arm("old", true))
        lease.started("old", "other", "https://elsewhere.com")
        assertFalse(lease.allowsRead("other", false, true))
        assertFalse(lease.allowsWait("other", true))
        val replacement = ConnectNavigationLease("old", "https://example.com")
        assertTrue(replacement.arm("old", true))
        replacement.started("old", "new", "https://example.com")
        replacement.started("new", "later", "https://example.com")
        assertFalse(replacement.allowsRead("later", false, true))
    }
}
