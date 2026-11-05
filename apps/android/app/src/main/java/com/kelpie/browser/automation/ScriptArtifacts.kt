package com.kelpie.browser.automation

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

/** The only transport locator is an opaque ID; file objects never enter responses. */
class ScriptArtifacts(
    private val directory: File,
) {
    data class Entry(
        val id: String,
        val file: File,
        val mimeType: String,
        val byteLength: Long,
        val sha256: String,
        val details: Map<String, Any?>,
    ) {
        fun manifest(partial: Boolean): Map<String, Any?> =
            details +
                mapOf(
                    "id" to id,
                    "mimeType" to mimeType,
                    "byteLength" to byteLength,
                    "sha256" to sha256,
                    "partial" to partial,
                )
    }

    private val entries = linkedMapOf<String, Entry>()
    private val owned = mutableSetOf<File>()

    init {
        Files.createDirectory(directory.toPath())
    }

    @Synchronized
    fun newFile(extension: String): File {
        require(extension in setOf("png", "gif", "mp4"))
        return File.createTempFile("artifact-", ".$extension", directory).also { owned.add(it) }
    }

    @Synchronized
    fun register(
        file: File,
        mimeType: String,
        details: Map<String, Any?>,
    ): Entry {
        if (file !in owned ||
            file.canonicalFile.parentFile != directory.canonicalFile ||
            Files.isSymbolicLink(file.toPath()) ||
            mimeType !in setOf("image/png", "image/gif", "video/mp4")
        ) {
            throw ScriptFailure("SCRIPT_ARTIFACT_INVALID")
        }
        if (entries.values.any { it.file == file }) throw ScriptFailure("SCRIPT_ARTIFACT_INVALID")
        val size = file.length()
        if (size <= 0 || size > 268_435_456) throw ScriptFailure("SCRIPT_ARTIFACT_INVALID")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val entry =
            Entry(
                UUID.randomUUID().toString(),
                file,
                mimeType,
                size,
                digest.digest().joinToString("") { "%02x".format(it) },
                details.toMap(),
            )
        entries[entry.id] = entry
        return entry
    }

    @Synchronized
    fun manifests(partial: Boolean): List<Map<String, Any?>> = entries.values.map { it.manifest(partial) }

    @Synchronized
    fun read(
        runId: String,
        body: Map<String, Any?>,
    ): Map<String, Any?> {
        if (body.keys.any { it !in setOf("runId", "artifactId", "offset", "length") }) {
            throw ScriptFailure("INVALID_PARAMS")
        }
        val id = body["artifactId"] as? String ?: throw ScriptFailure("INVALID_PARAMS")
        if (id.isEmpty() || id.length > 128) throw ScriptFailure("INVALID_PARAMS")
        val entry = entries[id] ?: throw ScriptFailure("SCRIPT_ARTIFACT_NOT_FOUND")
        val offset = integer(body["offset"], 0, 0, Long.MAX_VALUE)
        val length = integer(body["length"], 262_144, 1, 1_048_576).toInt()
        if (offset > entry.byteLength) throw ScriptFailure("SCRIPT_ARTIFACT_RANGE")
        val bytes = ByteArray(minOf(length.toLong(), entry.byteLength - offset).toInt())
        java.io.RandomAccessFile(entry.file, "r").use { file ->
            file.seek(offset)
            file.readFully(bytes)
        }
        val next = offset + bytes.size
        return mapOf(
            "success" to true,
            "runId" to runId,
            "artifactId" to entry.id,
            "data" to Base64.getEncoder().encodeToString(bytes),
            "offset" to offset,
            "nextOffset" to next,
            "eof" to (next == entry.byteLength),
            "mimeType" to entry.mimeType,
            "byteLength" to entry.byteLength,
            "sha256" to entry.sha256,
        )
    }

    @Synchronized
    fun retainedBytes(): Long = entries.values.sumOf { it.byteLength }

    /** Only files exclusively created by this instance are eligible for cleanup. */
    @Synchronized
    fun discardUnregistered() {
        val complete = entries.values.map { it.file }.toSet()
        owned.filter { it !in complete }.forEach { file ->
            if (file.canonicalFile.parentFile == directory.canonicalFile && !Files.isSymbolicLink(file.toPath())) file.delete()
        }
    }

    @Synchronized
    fun deleteOwned() {
        for (file in owned) {
            if (file.canonicalFile.parentFile == directory.canonicalFile && !Files.isSymbolicLink(file.toPath())) file.delete()
        }
        directory.delete()
        owned.clear()
        entries.clear()
    }

    private fun integer(
        value: Any?,
        default: Long,
        min: Long,
        max: Long,
    ): Long {
        if (value == null) return default
        val number = value as? Number ?: throw ScriptFailure("INVALID_PARAMS")
        val exact = number.toDouble()
        if (!exact.isFinite() || exact < min.toDouble() || exact > max.toDouble() || exact % 1.0 != 0.0) {
            throw ScriptFailure("INVALID_PARAMS")
        }
        val result = number.toLong()
        if (result < min || result > max) throw ScriptFailure("INVALID_PARAMS")
        return result
    }
}
