package com.kelpie.browser.automation

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.security.MessageDigest
import java.util.Base64

class ScriptOwnershipTest {
    @get:Rule val temporary = TemporaryFolder()

    private fun authority(
        owner: String = "a",
        grant: String = "grant",
        listener: String = "launch",
    ) = ScriptAuthority(ScriptOwner(owner, grant, listener)) { true }

    private fun script() =
        mapOf<String, Any?>(
            "version" to 1,
            "tabId" to "tab",
            "actions" to listOf(mapOf("action" to "wait", "ms" to 1)),
        )

    private fun fails(
        code: String,
        action: () -> Unit,
    ) {
        try {
            action()
            throw AssertionError("Expected refusal")
        } catch (failure: ScriptFailure) {
            assertEquals(code, failure.code)
        }
    }

    @Test
    fun ownerIncludesExactGrantAndListenerAndCannotBeForgedBySessionId() {
        val store = ScriptRunStore(temporary.newFolder("runs"))
        val owner = authority()
        val run = store.start(owner, script())
        assertEquals(run, store.owned(owner.owner, run.id))
        for (foreign in listOf(authority("b"), authority(grant = "new"), authority(listener = "restart"))) {
            fails("SCRIPT_NOT_FOUND") { store.owned(foreign.owner, run.id) }
            assertNull(store.owned(foreign.owner, null))
        }
        assertNotEquals(owner.owner, ScriptOwner("a", "new", "launch"))
        assertEquals("ScriptOwner", owner.owner.toString())
        run.finish(null, false)
        assertFalse(run.active())
        assertTrue(store.start(owner, script()).active())
    }

    @Test
    fun transportContextRevalidatesInsteadOfTrustingRequestFields() =
        runBlocking {
            var granted = true
            val owner = ScriptAuthority(ScriptOwner("a", "credential", "listener")) { granted }
            withContext(owner) { assertEquals(owner, currentScriptAuthority()) }
            granted = false
            try {
                withContext(owner) { currentScriptAuthority() }
                throw AssertionError("Revoked authority accepted")
            } catch (failure: ScriptFailure) {
                assertEquals("SCRIPT_AUTHORIZATION_REVOKED", failure.code)
            }
            try {
                currentScriptAuthority()
                throw AssertionError("Missing authority accepted")
            } catch (failure: ScriptFailure) {
                assertEquals("SCRIPT_AUTHORIZATION_REQUIRED", failure.code)
            }
        }

    @Test
    fun opaqueArtifactChunksHaveExactBytesAndStrictBounds() {
        val artifacts = ScriptArtifacts(File(temporary.root, "artifacts"))
        val file = artifacts.newFile("png")
        val bytes = ByteArray(1025) { it.toByte() }
        file.writeBytes(bytes)
        val entry = artifacts.register(file, "image/png", mapOf("width" to 1, "height" to 1))
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        assertEquals(hash, entry.sha256)
        val first = artifacts.read("run", mapOf("runId" to "run", "artifactId" to entry.id, "length" to 1000))
        val second = artifacts.read("run", mapOf("runId" to "run", "artifactId" to entry.id, "offset" to 1000))
        val decoded = Base64.getDecoder().decode(first["data"] as String) + Base64.getDecoder().decode(second["data"] as String)
        assertTrue(bytes.contentEquals(decoded))
        assertEquals(1000L, first["nextOffset"])
        assertEquals(true, second["eof"])
        assertFalse(entry.manifest(false).toString().contains(file.path))
        for (offset in listOf(-1, 1.5, Double.NaN, Double.POSITIVE_INFINITY, "0")) {
            fails("INVALID_PARAMS") { artifacts.read("run", mapOf("artifactId" to entry.id, "offset" to offset)) }
        }
        fails("INVALID_PARAMS") { artifacts.read("run", mapOf("artifactId" to entry.id, "length" to 1_048_577)) }
        fails("INVALID_PARAMS") { artifacts.read("run", mapOf("artifactId" to entry.id, "path" to "/secret")) }
        fails("SCRIPT_ARTIFACT_NOT_FOUND") { artifacts.read("run", mapOf("artifactId" to "../other")) }
        val keep = File(file.parentFile, "not-owned.txt").apply { writeText("keep") }
        artifacts.deleteOwned()
        assertEquals("keep", keep.readText())
        assertFalse(file.exists())
    }

    @Test
    fun terminalRetentionAndBudgetAreBounded() {
        var clock = 0L
        val store = ScriptRunStore(temporary.newFolder("retention")) { clock }
        val owner = authority()
        val run = store.start(owner, script())
        run.finish(null, false)
        clock = 31L * 60 * 1000
        store.retire()
        fails("SCRIPT_NOT_FOUND") { store.owned(owner.owner, run.id) }
        val budget = ScriptMediaBudget(1024)
        assertTrue(budget.take(1024))
        assertFalse(budget.take(1))
        assertFalse(budget.take(0))
    }

    @Test
    fun statusKeepsFinalizingActiveAndTerminalFailureMetadataOnly() {
        val run = ScriptRun("run", authority(), "tab", script(), File(temporary.root, "status"))
        run.step(0, "wait")
        run.finalizing()
        assertEquals(true, run.status()["playing"])
        assertEquals("finalizing", run.status()["state"])
        assertFalse(run.status().containsKey("runSuccess"))
        run.stop("SCRIPT_ABORTED")
        run.finish("SCRIPT_ABORTED", true)
        run.clearPrivate()
        val status = run.status()
        assertEquals(true, status["success"])
        assertEquals(false, status["playing"])
        assertEquals(false, status["runSuccess"])
        assertEquals("aborted", status["state"])
        assertEquals(0, status["actionIndex"])
        assertEquals(1, status["totalActions"])
        assertEquals(mapOf("code" to "SCRIPT_ABORTED", "message" to "Script stopped"), status["runError"])
        assertFalse(status.containsKey("error"))
        assertFalse(status.containsKey("outputs"))
        assertFalse(status.containsKey("tabId"))
        assertFalse(status.containsKey("currentActionName"))
        assertFalse(status.containsKey("phase"))
    }

    @Test
    fun captureDeadlineUsesCapturedOriginAndClearsWithPrivateState() {
        val run = ScriptRun("deadline", authority(), "tab", script(), File(temporary.root, "deadline"), startedNanos = System.nanoTime() - 1_000_000_000L)
        assertFalse(run.captureExpired())
        run.startCapture(0.0, 100)
        assertTrue(run.captureExpired())
        run.clearPrivate()
        assertFalse(run.captureExpired())
    }

    @Test
    fun privacyDiscardSurvivesRedactorFailureAndFirstUncertaintyWins() {
        val run = ScriptRun("privacy", authority(), "tab", script(), File(temporary.root, "privacy"))
        val file = run.artifacts.newFile("png").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        run.artifacts.register(file, "image/png", emptyMap())
        run.stop("SENSITIVE_CAPTURE_REFUSED")
        run.finish("SENSITIVE_CAPTURE_REFUSED", true)
        assertTrue(run.discardCapture.get())
        assertFalse(file.exists())
        assertEquals(emptyList<Any>(), run.status()["artifacts"])
        try {
            ScriptRedactor { null }.redact(mapOf("before" to "private"), emptyList())
            error("Redaction must fail closed")
        } catch (error: ScriptFailure) {
            assertEquals("OUTPUT_REDACTION_FAILED", error.code)
            run.stop(error.code)
            run.finish(error.code, false)
        }
        run.stop("SCRIPT_ABORTED")
        run.finish("SCRIPT_ABORTED", false)
        val status = run.status()
        assertEquals("SENSITIVE_CAPTURE_REFUSED", (status["runError"] as Map<*, *>)["code"])
        assertEquals(true, status["mayHaveCompleted"])
        assertEquals("failed", status["state"])
        assertTrue(run.discardCapture.get())
        assertFalse(status.containsKey("outputs"))
    }
}
