package com.kelpie.browser

import org.json.JSONArray
import org.json.JSONObject

internal data class AppRelease(
    val version: String,
    val url: String,
)

internal object ReleaseFeed {
    fun version(text: String): List<Int>? =
        if (text.matches(Regex("[0-9]{1,6}\\.[0-9]{1,6}\\.[0-9]{1,6}"))) {
            text.split('.').map(String::toInt)
        } else {
            null
        }

    fun allowedURL(url: String): Boolean {
        if (url.any(Char::isWhitespace) || url.contains('\\') || url.contains("..")) return false
        if (url.startsWith("https://github.com/UnlikeOtherAI/kelpie/releases/download/") &&
            url.none { it in "?#%" }
        ) {
            return url.endsWith(".apk")
        }
        return url == "https://play.google.com/store/apps/details?id=com.kelpie.browser"
    }

    private fun newer(
        candidate: List<Int>,
        current: List<Int>,
    ): Boolean {
        for (index in 0..2) {
            if (candidate[index] != current[index]) return candidate[index] > current[index]
        }
        return false
    }

    fun newest(
        feed: JSONArray,
        installed: String,
    ): AppRelease? {
        val current = version(installed) ?: return null
        var newest: AppRelease? = null
        for (index in 0 until feed.length()) {
            val release = feed.optJSONObject(index) ?: continue
            if (release.opt("draft") != false || release.opt("prerelease") != false) continue
            val notes = release.opt("body") as? String ?: continue
            for (part in notes.split("<!-- kelpie-update: ").drop(1)) {
                val end = part.indexOf(" -->")
                if (end < 0) continue
                val item = runCatching { JSONObject(part.substring(0, end)) }.getOrNull() ?: continue
                if (item.opt("target") != "android") continue
                val text = item.opt("version") as? String ?: continue
                val number = version(text) ?: continue
                val url = item.opt("url") as? String ?: continue
                if (!newer(number, current) || !allowedURL(url)) continue
                if (newest == null || newer(number, version(newest.version)!!)) newest = AppRelease(text, url)
            }
        }
        return newest
    }
}
