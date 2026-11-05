package com.kelpie.browser.automation

import java.util.concurrent.atomic.AtomicBoolean

/** At most one system copy may own a bitmap, including a timed-out copy. */
internal object ScriptPixelCopySlot {
    private val occupied = AtomicBoolean(false)

    fun acquire(): Boolean = occupied.compareAndSet(false, true)

    fun release() {
        check(occupied.compareAndSet(true, false))
    }
}

/** Late completion can retire private storage, never publish it. */
internal class ScriptPixelCopyGate(
    private val recycle: () -> Unit,
    private val release: () -> Unit,
) {
    private enum class State { PENDING, READY, ABANDONED, CLAIMED, RETIRED }

    private var state = State.PENDING

    @Synchronized
    fun complete() {
        when (state) {
            State.PENDING -> state = State.READY
            State.ABANDONED -> retire()
            else -> error("Unexpected PixelCopy completion")
        }
    }

    @Synchronized
    fun claim(): Boolean {
        if (state != State.READY) return false
        state = State.CLAIMED
        release()
        return true
    }

    @Synchronized
    fun abandon() {
        when (state) {
            State.PENDING -> state = State.ABANDONED
            State.READY -> retire()
            else -> Unit
        }
    }

    private fun retire() {
        state = State.RETIRED
        recycle()
        release()
    }
}
