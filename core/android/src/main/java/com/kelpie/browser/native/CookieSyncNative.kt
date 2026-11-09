package com.kelpie.browser.nativecore

/**
 * JNI boundary over core-sync (`core/native/core-sync/include/kelpie/sync_c_api.h`).
 * JSON in, JSON out. A store is not thread-safe: [com.kelpie.browser.sync.SyncStore]
 * runs every call for one handle on one thread.
 *
 * JVM unit tests load a host build of the same JNI source through the
 * `kelpie.sync.jni` system property; the app loads the bundled `kelpie_jni`.
 */
object CookieSyncNative {
    init {
        val hostLibrary = System.getProperty("kelpie.sync.jni")
        if (hostLibrary.isNullOrEmpty()) System.loadLibrary("kelpie_jni") else System.load(hostLibrary)
    }

    external fun storeOpen(
        path: String,
        options: String,
    ): String

    external fun storeClose(handle: Long)

    external fun storeStatus(handle: Long): String

    external fun storeFinishWarmup(handle: Long)

    external fun storeScan(
        handle: Long,
        cookies: String,
        coverage: String,
        now: Long,
    ): String

    external fun storeAnswerPull(
        handle: Long,
        pull: String,
        cookies: String,
        coverage: String,
        now: Long,
    ): String

    external fun storeBuildPush(
        handle: Long,
        watermark: String,
        cookies: String,
        coverage: String,
        now: Long,
    ): String

    external fun storePlanMerge(
        handle: Long,
        records: String,
        source: String?,
        now: Long,
    ): String

    external fun storeCommitMerge(
        handle: Long,
        results: String,
    ): String

    external fun storeAbortMerge(handle: Long)

    external fun storeWatermark(
        handle: Long,
        replica: String,
    ): String

    external fun validate(
        kind: String,
        json: String,
    ): String

    external fun transcript(pair: String): String

    external fun accountHints(
        subject: String,
        now: Long,
    ): String

    external fun canonicalCookie(cookie: String): String
}
