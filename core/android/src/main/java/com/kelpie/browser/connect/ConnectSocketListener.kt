package com.kelpie.browser.connect

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.atomic.AtomicBoolean

/** Transport callbacks revoke mutation authority before the main dispatcher consumes queued work. */
internal class ConnectSocketListener(
    private val frames: Channel<String>,
    private val opened: CompletableDeferred<Unit>,
    private val authority: AtomicBoolean,
) : WebSocketListener() {
    override fun onOpen(
        webSocket: WebSocket,
        response: Response,
    ) {
        opened.complete(Unit)
    }

    override fun onMessage(
        webSocket: WebSocket,
        text: String,
    ) {
        if (text.toByteArray().size > 1024 * 1024 || frames.trySend(text).isFailure) {
            authority.set(false)
            frames.close(IllegalStateException("Invalid gateway frame"))
            webSocket.close(1008, "Frame limit exceeded")
        }
    }

    override fun onMessage(
        webSocket: WebSocket,
        bytes: ByteString,
    ) {
        if (bytes.size > 1024 * 1024) {
            authority.set(false)
            frames.close(IllegalStateException("Invalid gateway frame"))
            webSocket.close(1008, "Frame limit exceeded")
        } else {
            onMessage(webSocket, bytes.utf8())
        }
    }

    override fun onClosing(
        webSocket: WebSocket,
        code: Int,
        reason: String,
    ) {
        authority.set(false)
        webSocket.close(code, null)
        opened.completeExceptionally(IllegalStateException("Gateway closed"))
        frames.close()
    }

    override fun onFailure(
        webSocket: WebSocket,
        t: Throwable,
        response: Response?,
    ) {
        authority.set(false)
        opened.completeExceptionally(IllegalStateException("Gateway unavailable"))
        frames.close(IllegalStateException("Gateway unavailable"))
    }
}
