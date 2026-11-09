package com.kelpie.browser.sync

import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.ApplicationCallPipeline
import io.ktor.server.application.call
import io.ktor.server.engine.ApplicationEngine
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.origin
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.header
import io.ktor.server.response.respondText
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.utils.io.core.readBytes
import io.ktor.utils.io.readRemaining
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The sync-only listener: `POST /v1/sync/{hello,auth,exchange}` on an ephemeral
 * port, separate from the automation server. Admission runs before any body
 * byte is read: the peer-address rule, header checks, size limits, the hello
 * rate limits and, for exchange, a live session.
 */
class SyncListener(
    private val responder: SyncResponder,
    private val addresses: SyncAddressRule,
    private val clock: () -> Long,
) {
    private var engine: ApplicationEngine? = null
    private val hellos =
        SyncRateLimiter(clock, perKey = SyncProtocol.HELLO_PER_SOURCE_PER_MIN, total = SyncProtocol.HELLO_TOTAL_PER_MIN)

    /** Starts listening and returns the bound port. */
    suspend fun start(): Int {
        // Dual-stack first so IPv6 link-local peers can reach us; IPv4 only when IPv6 is off.
        val server =
            listOf("::", "0.0.0.0").firstNotNullOfOrNull { host ->
                val candidate = create(host)
                runCatching { candidate.start(wait = false) }
                    .onFailure { runCatching { candidate.stop(0, 0) } }
                    .map { candidate }
                    .getOrNull()
            } ?: throw SyncFailure("LISTENER", "cannot bind the sync listener")
        engine = server
        return server.resolvedConnectors().first().port
    }

    fun stop() {
        engine?.stop(0, 500)
        engine = null
    }

    private fun create(host: String): ApplicationEngine =
        embeddedServer(
            factory = Netty,
            port = 0,
            host = host,
            configure = {
                maxInitialLineLength = 4096
                maxHeaderSize = 16 * 1024
                maxChunkSize = 64 * 1024
            },
        ) {
            // Every response, including 404 and 405, is uncacheable.
            intercept(ApplicationCallPipeline.Plugins) { call.response.header(HttpHeaders.CacheControl, "no-store") }
            routing {
                for ((path, kind) in ROUTES) {
                    route(path) {
                        post { handle(call, kind) }
                        handle { respond(call, SyncReply(405, SyncProtocol.error("METHOD_NOT_ALLOWED"))) }
                    }
                }
            }
        }

    private companion object {
        val ROUTES = listOf("/v1/sync/hello" to Kind.HELLO, "/v1/sync/auth" to Kind.AUTH, "/v1/sync/exchange" to Kind.EXCHANGE)
    }

    private enum class Kind(
        val limit: Long,
        val deadline: Long,
    ) {
        HELLO(SyncProtocol.SMALL_BODY_BYTES, SyncProtocol.SMALL_READ_DEADLINE_MS),
        AUTH(SyncProtocol.SMALL_BODY_BYTES, SyncProtocol.SMALL_READ_DEADLINE_MS),
        EXCHANGE(SyncProtocol.EXCHANGE_BODY_BYTES, SyncProtocol.EXCHANGE_READ_DEADLINE_MS),
    }

    private suspend fun handle(
        call: ApplicationCall,
        kind: Kind,
    ) {
        val source = call.request.origin.remoteAddress
        val headers = call.request.headers
        val verdict =
            SyncRequestGate.check(
                SyncRequestGate.Request(
                    sourcePermitted = addresses.permits(source),
                    hasOrigin = headers.contains(HttpHeaders.Origin),
                    hasTransferEncoding = headers.contains(HttpHeaders.TransferEncoding),
                    contentLengths = headers.getAll(HttpHeaders.ContentLength).orEmpty(),
                    contentType = headers[HttpHeaders.ContentType],
                    limit = kind.limit,
                ),
            )
        if (verdict != null) return respond(call, SyncReply(verdict.first, SyncProtocol.error(verdict.second)))
        val session =
            if (kind == Kind.EXCHANGE) {
                responder.session(headers[SyncProtocol.SESSION_HEADER])
                    ?: return respond(call, SyncReply(401, SyncProtocol.error("SYNC_SESSION")))
            } else {
                null
            }
        if (kind == Kind.HELLO && !hellos.tryAcquire(source)) return respond(call, SyncReply(429, SyncProtocol.error("RATE_LIMITED")))
        val length = headers[HttpHeaders.ContentLength]!!.trim().toLong()
        val body = read(call, length, kind.deadline) ?: return respond(call, SyncReply(408, SyncProtocol.error("TIMEOUT")))
        val message = SyncJson.parseObject(body) ?: return respond(call, SyncReply(400, SyncProtocol.error("INVALID_MESSAGE")))
        val reply =
            try {
                when (kind) {
                    Kind.HELLO -> responder.hello(message)
                    Kind.AUTH -> responder.auth(message)
                    Kind.EXCHANGE -> responder.exchange(session!!, message)
                }
            } catch (failure: SyncFailure) {
                SyncReply(if (failure.code == "STALE") 503 else 500, SyncProtocol.error(if (failure.code == "STALE") "UNAVAILABLE" else "INTERNAL"))
            }
        respond(call, reply)
    }

    /** Reads exactly [length] bytes within [deadline]; null when the peer is too slow or short. */
    private suspend fun read(
        call: ApplicationCall,
        length: Long,
        deadline: Long,
    ): String? =
        withTimeoutOrNull(deadline) {
            val bytes = call.receiveChannel().readRemaining(length + 1).readBytes()
            if (bytes.size.toLong() != length) null else bytes.toString(Charsets.UTF_8)
        }

    private suspend fun respond(
        call: ApplicationCall,
        reply: SyncReply,
    ) {
        call.respondText(reply.body.toString(), ContentType.Application.Json, HttpStatusCode.fromValue(reply.status))
    }
}

/** Header admission for sync requests, kept apart from Ktor so it is unit-testable. */
object SyncRequestGate {
    data class Request(
        val sourcePermitted: Boolean,
        val hasOrigin: Boolean,
        val hasTransferEncoding: Boolean,
        val contentLengths: List<String>,
        val contentType: String?,
        val limit: Long,
    )

    /** Returns the refusal (status, code), or null to admit. */
    fun check(request: Request): Pair<Int, String>? {
        if (!request.sourcePermitted) return 403 to "FORBIDDEN"
        if (request.hasOrigin) return 403 to "FORBIDDEN"
        if (request.hasTransferEncoding) return 400 to "BAD_REQUEST"
        if (request.contentLengths.size > 1 || request.contentLengths.any { it.contains(',') }) return 400 to "BAD_REQUEST"
        val length = request.contentLengths.firstOrNull() ?: return 411 to "LENGTH_REQUIRED"
        val bytes = length.trim().toLongOrNull()?.takeIf { it >= 0 } ?: return 400 to "BAD_REQUEST"
        if (bytes > request.limit) return 413 to "PAYLOAD_TOO_LARGE"
        val type =
            request.contentType
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase()
        if (type != "application/json") return 415 to "UNSUPPORTED_MEDIA_TYPE"
        return null
    }
}
