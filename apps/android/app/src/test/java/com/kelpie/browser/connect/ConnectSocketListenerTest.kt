package com.kelpie.browser.connect

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import okhttp3.Request
import okhttp3.WebSocket
import okio.ByteString
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

class ConnectSocketListenerTest {
    private class Socket : WebSocket {
        var closed = false

        override fun request(): Request = Request.Builder().url("https://example.test/").build()

        override fun queueSize(): Long = 0

        override fun send(text: String): Boolean = true

        override fun send(bytes: ByteString): Boolean = true

        override fun close(
            code: Int,
            reason: String?,
        ): Boolean {
            closed = true
            return true
        }

        override fun cancel() {}
    }

    @Test
    fun revocationFencesAlreadyQueuedCommands() {
        val frames = Channel<String>(2)
        val authority = AtomicBoolean(true)
        val listener = ConnectSocketListener(frames, CompletableDeferred(), authority)
        listener.onMessage(Socket(), "queued")
        listener.onClosing(Socket(), 1008, "")
        assertFalse(authority.get())
        assertTrue(frames.tryReceive().isSuccess)
    }

    @Test
    fun failedOldSocketCannotRevokeNewSocketAuthority() {
        val old = AtomicBoolean(true)
        val current = AtomicBoolean(true)
        ConnectSocketListener(Channel(1), CompletableDeferred(), old).onFailure(Socket(), IOException(), null)
        assertFalse(old.get())
        assertTrue(current.get())
    }

    @Test
    fun oversizedFramesRevokeAndCloseBeforeDispatch() {
        val authority = AtomicBoolean(true)
        val socket = Socket()
        val listener = ConnectSocketListener(Channel(1), CompletableDeferred(), authority)
        listener.onMessage(socket, "x".repeat(1024 * 1024 + 1))
        assertFalse(authority.get())
        assertTrue(socket.closed)
    }
}
