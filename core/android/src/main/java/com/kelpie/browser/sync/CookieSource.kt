package com.kelpie.browser.sync

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

/** Where a metadata entry lives; Android turns these into coverage URLs. */
data class EntryLocation(
    val domain: String,
    val path: String,
)

/** Engine cookies in wire shape plus the honest coverage of the read that produced them. */
class CookieSnapshot(
    val cookies: JsonArray,
    val coverage: JsonObject,
)

/**
 * The default cookie store as core-sync sees it. Every method is blocking and
 * runs on the store thread, so a merge transaction holds the store from plan to
 * commit. Implementations throw when any read fails; a failed read is never an
 * empty result.
 */
interface CookieSource {
    /**
     * Reads the store. [entries] are the metadata entries' locations; [hosts]
     * limits the read to those hosts (null reads every known location).
     * [discover] adds locations that only find new cookies (Android: history
     * hosts); pull and push answers skip them to stay cheap.
     */
    fun snapshot(
        entries: List<EntryLocation>,
        hosts: Set<String>? = null,
        discover: Boolean = true,
    ): CookieSnapshot

    /**
     * Applies one planned op (`{"id","op","cookie"}`) and returns
     * `{"id","ok","readback"}` per the read-back contract.
     */
    fun apply(
        op: JsonObject,
        entries: List<EntryLocation>,
    ): JsonObject
}
