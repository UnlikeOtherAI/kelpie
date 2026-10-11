package com.kelpie.browser.network

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

/** Cancellation may finish the caller while renderer work still owns the shared execution lease. */
suspend fun <T> withBrowserGatewayLease(lock: Mutex, retirement: BrowserGatewayRetirement?, block: suspend () -> T): T {
    val owner = Any()
    lock.lock(owner)
    try {
        return block()
    } finally {
        val pending = retirement?.waitForPending()
        if (pending == null) lock.unlock(owner)
        else CoroutineScope(Dispatchers.Default).launch {
            try { pending.await() } finally { lock.unlock(owner) }
        }
    }
}

/** Tracks renderer work past caller cancellation; callback or confirmed renderer teardown retires its lease. */
class BrowserGatewayRetirement {
    private data class Work(val target: Any, val cancel: () -> Unit)
    private val pending = mutableMapOf<Any, Work>()
    private var idle = CompletableDeferred<Unit>().apply { complete(Unit) }

    @Synchronized fun start(target: Any, cancel: () -> Unit): Any {
        if (pending.isEmpty()) idle = CompletableDeferred()
        val ticket = Any()
        pending[ticket] = Work(target, cancel)
        return ticket
    }

    @Synchronized fun complete(ticket: Any) {
        pending.remove(ticket)
        if (pending.isEmpty()) idle.complete(Unit)
    }

    @Synchronized fun waitForPending(): Deferred<Unit>? = if (pending.isEmpty()) null else idle

    fun retireTarget(target: Any) {
        val cancelled = synchronized(this) {
            val tickets = pending.filterValues { it.target === target }
            tickets.keys.forEach { pending.remove(it) }
            if (pending.isEmpty()) idle.complete(Unit)
            tickets.values.toList()
        }
        cancelled.forEach { it.cancel() }
    }
}
