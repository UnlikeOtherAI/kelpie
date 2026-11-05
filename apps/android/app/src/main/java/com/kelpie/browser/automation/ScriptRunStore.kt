package com.kelpie.browser.automation

import java.io.File
import java.nio.file.Files
import java.util.UUID

/** Bounded in-memory run metadata and app-private artifact retention. */
class ScriptRunStore(
    private val root: File,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val runs = linkedMapOf<String, ScriptRun>()

    init {
        Files.createDirectories(root.toPath())
    }

    @Synchronized
    fun start(
        authority: ScriptAuthority,
        script: Map<String, Any?>,
    ): ScriptRun {
        retire()
        if (runs.values.any { it.active() }) throw ScriptFailure("RECORDING_IN_PROGRESS")
        val id = UUID.randomUUID().toString()
        val run = ScriptRun(id, authority, script["tabId"] as String, script, File(root, id), createdAtMs = now())
        runs[id] = run
        return run
    }

    @Synchronized
    fun owned(
        owner: ScriptOwner,
        id: String?,
    ): ScriptRun? {
        retire()
        if (id != null && (id.isEmpty() || id.length > 128)) throw ScriptFailure("INVALID_PARAMS")
        if (id != null) {
            return runs[id]?.takeIf { it.owner == owner } ?: throw ScriptFailure("SCRIPT_NOT_FOUND")
        }
        return runs.values.lastOrNull { it.owner == owner }
    }

    @Synchronized
    fun active(): Boolean = runs.values.any { it.active() }

    @Synchronized
    fun stopActive() {
        runs.values.filter { it.active() }.forEach { it.stop("SCRIPT_ABORTED") }
    }

    @Synchronized
    fun retire() {
        val terminal = runs.values.filter { !it.active() }
        val expired = terminal.filter { now() - it.createdAtMs > 30 * 60 * 1000 }
        val keep = terminal.filter { it !in expired }.toMutableList()
        var bytes = keep.sumOf { it.artifacts.retainedBytes() }
        val discard = expired.toMutableList()
        while (keep.size > 4 || bytes > 268_435_456) {
            val oldest = keep.removeAt(0)
            bytes -= oldest.artifacts.retainedBytes()
            discard.add(oldest)
        }
        for (run in discard) {
            run.artifacts.deleteOwned()
            runs.remove(run.id)
        }
    }
}
