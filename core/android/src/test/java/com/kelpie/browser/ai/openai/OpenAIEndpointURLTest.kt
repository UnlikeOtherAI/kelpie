package com.kelpie.browser.ai.openai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OpenAIEndpointURLTest {
    private fun norm(input: String) = OpenAIEndpointURL.normalize(input).baseURL

    private fun assertInvalid(input: String) {
        try {
            OpenAIEndpointURL.normalize(input)
            fail("Expected INVALID_ENDPOINT_URL for '$input'")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.INVALID_ENDPOINT_URL, e.code)
        }
    }

    @Test
    fun contractExamples() {
        assertEquals("http://127.0.0.1:18880/v1", norm("http://127.0.0.1:18880/v1/"))
        assertEquals("http://studio.local:1234/v1", norm("http://studio.local:1234"))
        assertEquals("https://host/openai/v1", norm("https://host/openai/v1/chat/completions"))
        assertEquals("http://[::1]:8080/v1", norm("http://[::1]:8080/v1"))
    }

    @Test
    fun trailingAndDuplicateSlashesCollapse() {
        assertEquals("http://h:1/v1", norm("  http://h:1//v1///  "))
        assertEquals("http://h/v1", norm("http://h/"))
        assertEquals("http://h/v1", norm("http://h"))
    }

    @Test
    fun pastedOperationsAreStripped() {
        assertEquals("http://h/v1", norm("http://h/v1/models"))
        assertEquals("http://h/v1", norm("http://h/v1/completions"))
        assertEquals("http://h/v1", norm("http://h/v1/embeddings/"))
        assertEquals("http://h/v1", norm("http://h/chat/completions"))
        assertEquals("http://h/api/V1", norm("http://h/api/V1/Chat/Completions"))
    }

    @Test
    fun joinNeverDuplicatesV1OrSlashes() {
        val url = OpenAIEndpointURL.normalize("http://h:8080/v1/")
        assertEquals("http://h:8080/v1/models", url.join("models"))
        assertEquals("http://h:8080/v1/chat/completions", url.join("/chat/completions"))
        assertFalse(url.join("models").contains("/v1/v1"))
        assertFalse(url.join("models").substringAfter("://").contains("//"))
    }

    @Test
    fun schemeAndHostLowerCasedPathCaseKept() {
        assertEquals("https://studio.local/OpenAI/V1", norm("HTTPS://Studio.LOCAL/OpenAI/V1"))
    }

    @Test
    fun ipv6AndLocalHosts() {
        val v6 = OpenAIEndpointURL.normalize("http://[FE80::1]:11434")
        assertEquals("fe80::1", v6.host)
        assertEquals("http://[fe80::1]:11434/v1", v6.baseURL)
        assertTrue(OpenAIEndpointURL.normalize("http://[::1]/v1").isLoopback)
        assertTrue(OpenAIEndpointURL.normalize("http://localhost:1234").isLoopback)
        assertTrue(OpenAIEndpointURL.normalize("http://127.0.0.5:1234").isLoopback)
        assertFalse(OpenAIEndpointURL.normalize("http://mac-studio.local:1234").isLoopback)
        assertFalse(OpenAIEndpointURL.normalize("http://192.168.1.20:8080").isLoopback)
    }

    @Test
    fun rejectsInvalidInput() {
        assertInvalid("")
        assertInvalid("   ")
        assertInvalid("ftp://host/v1")
        assertInvalid("host:8080/v1")
        assertInvalid("http://")
        assertInvalid("http:///v1")
        assertInvalid("http://user:pass@host/v1")
        assertInvalid("http://host/v1?key=1")
        assertInvalid("http://host/v1#frag")
        assertInvalid("http://host:0/v1")
        assertInvalid("http://host:65536/v1")
        assertInvalid("http://host:abc/v1")
        assertInvalid("http://host:/v1")
        assertInvalid("http://::1:8080/v1")
        assertInvalid("http://[::1/v1")
        assertInvalid("http://bad host/v1")
    }

    @Test
    fun acceptsPortBounds() {
        assertEquals("http://h:1/v1", norm("http://h:1"))
        assertEquals("http://h:65535/v1", norm("http://h:65535"))
    }
}
