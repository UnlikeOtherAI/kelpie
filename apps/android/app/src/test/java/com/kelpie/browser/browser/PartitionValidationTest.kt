package com.kelpie.browser.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class PartitionValidationTest {
    @Test
    fun defaultAndNamedStoresAreExplicit() {
        assertNull(PartitionRegistry.validate(emptyMap()).partition)
        assertEquals("team.one", PartitionRegistry.validate(mapOf("partition" to "team.one")).partition)
        assertEquals("Team", PartitionRegistry.validate(mapOf("name" to "Team")).name)
    }

    @Test
    fun invalidOrUnsupportedIsolationNeverBecomesDefault() {
        for (body in listOf(
            mapOf("partition" to "../escape"), mapOf("partition" to "default"), mapOf("partition" to "ephemeral-hidden"),
            mapOf("partition" to 42), mapOf("partition" to "private", "persistent" to false),
            mapOf("partition" to "private", "persistent" to "false"),
        )) {
            try {
                PartitionRegistry.validate(body)
                fail("Accepted invalid isolation: $body")
            } catch (_: PartitionRegistry.Failure) { }
        }
    }
}
