package com.kelpie.browser.nativecore

/** Thin JNI ownership boundary; canonical schemas and transaction state stay in core-mcp. */
object BrowserGatewayNative : BrowserGatewayAbi {
    init {
        System.loadLibrary("kelpie_jni")
    }

    external override fun create(config: String): Long

    external override fun destroy(handle: Long)

    external override fun begin(
        handle: Long,
        request: String,
        mcp: Boolean,
    ): String

    external override fun advance(
        handle: Long,
        result: String,
    ): String

    external override fun cancel(handle: Long): String

    external override fun invalidate(
        handle: Long,
        tab: String?,
    )

    external fun extensions(): String
}

interface BrowserGatewayAbi {
    fun create(config: String): Long

    fun destroy(handle: Long)

    fun begin(
        handle: Long,
        request: String,
        mcp: Boolean,
    ): String

    fun advance(
        handle: Long,
        result: String,
    ): String

    fun cancel(handle: Long): String

    fun invalidate(
        handle: Long,
        tab: String?,
    )
}
