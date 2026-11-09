package com.kelpie.browser.sync

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.InetAddress
import java.security.MessageDigest

/**
 * A fake UOA. A ticket is a deterministic function of subject, challenge and
 * client id; validation recomputes it with the validating account's subject, so
 * it checks all three and that both devices share one subject.
 */
class FakeUOA {
    val calls =
        java.util.concurrent.atomic
            .AtomicInteger()

    fun ticket(
        subject: String,
        challenge: String,
        clientId: String,
    ): String =
        MessageDigest
            .getInstance("SHA-256")
            .digest("fake-uoa\u0000$subject\u0000$challenge\u0000$clientId".toByteArray())
            .joinToString("") { "%02x".format(it) }

    fun account(
        subject: String,
        ticketSubject: String? = null,
    ) = Account(this, subject, ticketSubject)

    /** [ticketSubject] overrides the signed-in subject only for an impostor. */
    class Account(
        private val uoa: FakeUOA,
        subject: String,
        private val ticketSubject: String?,
    ) : SyncAccount {
        override val identity =
            MutableStateFlow<SyncIdentity?>(
                SyncIdentity(
                    subject,
                    java.util.UUID
                        .randomUUID()
                        .toString(),
                ),
            )

        fun signOut() {
            identity.value = null
        }

        fun signIn(subject: String) {
            identity.value =
                SyncIdentity(
                    subject,
                    java.util.UUID
                        .randomUUID()
                        .toString(),
                )
        }

        override suspend fun issueTicket(
            identity: SyncIdentity,
            challenge: String,
            clientId: String,
        ): String {
            uoa.calls.incrementAndGet()
            if (this.identity.value != identity) throw SyncFailure("STALE")
            return uoa.ticket(ticketSubject ?: identity.subject, challenge, clientId)
        }

        override suspend fun validateTicket(
            identity: SyncIdentity,
            ticket: String,
            challenge: String,
            clientId: String,
        ): Boolean {
            uoa.calls.incrementAndGet()
            if (this.identity.value != identity) throw SyncFailure("STALE")
            return ticket == uoa.ticket(identity.subject, challenge, clientId)
        }
    }
}

/** An in-memory default store that enumerates fully (`{"all":true}`). */
class MemoryCookies : CookieSource {
    data class Cookie(
        val domain: String,
        val path: String,
        val name: String,
        val value: String,
        val expires: Long?,
    )

    private val cookies = linkedMapOf<Triple<String, String, String>, Cookie>()

    @Synchronized fun put(
        domain: String,
        name: String,
        value: String,
        expires: Long? = 4_102_444_800L,
        path: String = "/",
    ) {
        cookies[Triple(domain, path, name)] = Cookie(domain, path, name, value, expires)
    }

    @Synchronized fun remove(
        domain: String,
        name: String,
        path: String = "/",
    ) {
        cookies.remove(Triple(domain, path, name))
    }

    @Synchronized fun value(
        domain: String,
        name: String,
        path: String = "/",
    ): String? = cookies[Triple(domain, path, name)]?.value

    /** A process restart: session cookies are gone. */
    @Synchronized fun dropSessionCookies() {
        cookies.values.removeAll { it.expires == null }
    }

    @Synchronized override fun snapshot(
        entries: List<EntryLocation>,
        hosts: Set<String>?,
    ): CookieSnapshot =
        CookieSnapshot(
            JsonArray(cookies.values.map(::wire)),
            buildJsonObject { put("all", true) },
        )

    @Synchronized override fun apply(
        op: JsonObject,
        entries: List<EntryLocation>,
    ): JsonObject {
        val cookie = op.obj("cookie")!!
        val key = Triple(cookie.string("domain")!!, cookie.string("path") ?: "/", cookie.string("name")!!)
        if (op.string("op") == "delete") {
            cookies.remove(key)
        } else {
            cookies[key] = Cookie(key.first, key.second, key.third, cookie.string("value")!!, cookie.long("expires"))
        }
        val host = key.first.removePrefix(".")
        val readback = cookies.values.filter { it.name == key.third && it.domain.removePrefix(".") == host }.map(::wire)
        return buildJsonObject {
            put("id", op["id"]!!)
            put("ok", true)
            put("readback", JsonArray(readback))
        }
    }

    private fun wire(cookie: Cookie) =
        buildJsonObject {
            put("domain", cookie.domain)
            put("path", cookie.path)
            put("name", cookie.name)
            put("value", cookie.value)
            put("expires", cookie.expires)
            put("secure", true)
            put("httpOnly", true)
            put("sameSite", "Lax")
        }
}

/** mDNS stand-in: every started service sees every other one on 127.0.0.1. */
class LoopbackDiscovery(
    private val network: Network,
) : SyncDiscovery {
    class Network {
        val members = mutableListOf<LoopbackDiscovery>()
    }

    private var advert: SyncDiscovery.Advert? = null
    private var listener: SyncDiscovery.Listener? = null

    private fun found(advert: SyncDiscovery.Advert) = SyncDiscovery.Found(advert.replica, advert.hint, listOf(InetAddress.getLoopbackAddress()), advert.port)

    override fun start(
        advert: SyncDiscovery.Advert,
        listener: SyncDiscovery.Listener,
    ) {
        val others =
            synchronized(network) {
                this.advert = advert
                this.listener = listener
                if (this !in network.members) network.members.add(this)
                network.members.filter { it !== this && it.advert != null }
            }
        others.forEach { other ->
            other.advert?.let { listener.found(found(it)) }
            other.listener?.found(found(advert))
        }
    }

    override fun update(advert: SyncDiscovery.Advert) {
        start(advert, listener ?: return)
    }

    override fun stop() {
        val (gone, others) =
            synchronized(network) {
                val gone = advert
                advert = null
                listener = null
                network.members.remove(this)
                gone to network.members.toList()
            }
        if (gone != null) others.forEach { it.listener?.lost(gone.replica) }
    }
}
