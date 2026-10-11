package com.kelpie.browser.connect

/** One native navigation may transfer only its fixed completion reads to one new document. */
class ConnectNavigationLease(private val initialVersion: String, private val expectedUrl: String?) {
    private var armed = false
    private var invalid = false
    private var destination: String? = null

    fun arm(version: String, authorized: Boolean): Boolean {
        if (!authorized || version != initialVersion || armed) return false
        armed = true
        return true
    }

    fun started(previous: String, version: String, url: String) {
        if (!armed || invalid || destination != null || previous != initialVersion ||
            expectedUrl == null || url.trimEnd('/') != expectedUrl.trimEnd('/')) {
            invalid = true
            return
        }
        destination = version
    }

    fun allowsRead(version: String, loading: Boolean, authorized: Boolean): Boolean =
        armed && !invalid && authorized && !loading &&
            version == (destination ?: initialVersion.takeIf { expectedUrl == null })

    fun allowsWait(version: String, authorized: Boolean): Boolean =
        armed && !invalid && authorized && (destination == null || version == destination)
}
