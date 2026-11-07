package com.kelpie.browser.connect

import org.junit.Assert.assertEquals
import org.junit.Test

class ConnectTextTest {
    @Test
    fun wireBoundsPreserveUnicode() {
        assertEquals(120, ConnectText.bounded("😀".repeat(100), 120).length)
        assertEquals("a", ConnectText.bounded("a😀", 2))
        assertEquals("�", ConnectText.bounded("\uD800", 120))
    }
}
