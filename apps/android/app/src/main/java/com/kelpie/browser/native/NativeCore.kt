package com.kelpie.browser.nativecore

object NativeCore {
    init {
        System.loadLibrary("kelpie_jni")
    }

    fun bookmarkStoreCreate(): Long =
        bookmarkStoreCreateNative().also { check(it != 0L) { "Failed to create bookmark store" } }

    fun historyStoreCreate(): Long =
        historyStoreCreateNative().also { check(it != 0L) { "Failed to create history store" } }

    fun networkTrafficStoreCreate(): Long =
        networkTrafficStoreCreateNative().also { check(it != 0L) { "Failed to create network traffic store" } }

    private external fun bookmarkStoreCreateNative(): Long
    external fun bookmarkStoreDestroyNative(handle: Long)
    external fun bookmarkStoreAdd(handle: Long, title: String, url: String)
    external fun bookmarkStoreRemove(handle: Long, id: String)
    external fun bookmarkStoreRemoveAll(handle: Long)
    external fun bookmarkStoreToJson(handle: Long): String?
    external fun bookmarkStoreCount(handle: Long): Int
    external fun bookmarkStoreLoadJson(handle: Long, json: String?)

    private external fun historyStoreCreateNative(): Long
    external fun historyStoreDestroyNative(handle: Long)
    external fun historyStoreRecord(handle: Long, url: String, title: String)
    external fun historyStoreClear(handle: Long)
    external fun historyStoreUpdateLatestTitle(handle: Long, url: String, title: String)
    external fun historyStoreToJson(handle: Long): String?
    external fun historyStoreCount(handle: Long): Int
    external fun historyStoreLoadJson(handle: Long, json: String?)

    private external fun networkTrafficStoreCreateNative(): Long
    external fun networkTrafficStoreDestroyNative(handle: Long)
    external fun networkTrafficStoreAppendJson(handle: Long, entryJson: String): Boolean
    external fun networkTrafficStoreAppendDocumentNavigation(
        handle: Long,
        url: String,
        statusCode: Int,
        contentType: String,
        responseHeadersJson: String?,
        size: Long,
        startTime: String?,
        duration: Int,
    )
    external fun networkTrafficStoreClear(handle: Long)
    external fun networkTrafficStoreSelect(handle: Long, index: Int): Boolean
    external fun networkTrafficStoreSelectedIndex(handle: Long): Int
    external fun networkTrafficStoreGetSelectedJson(handle: Long): String?
    external fun networkTrafficStoreToJson(handle: Long): String?
    external fun networkTrafficStoreToSummaryJson(
        handle: Long,
        method: String?,
        category: String?,
        statusRange: String?,
        urlPattern: String?,
    ): String?
    external fun networkTrafficStoreCount(handle: Long): Int
    external fun networkTrafficStoreLoadJson(handle: Long, json: String?)
}
