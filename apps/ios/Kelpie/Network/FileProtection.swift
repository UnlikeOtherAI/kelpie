import Foundation

/// Applies iOS Data Protection so files written by Kelpie are encrypted while
/// the device is locked.
///
/// `NSFileProtectionComplete` is the strongest class: the file's encryption key
/// is evicted from memory shortly after the device locks, so the contents are
/// unreadable until the user next unlocks. This is the correct default for any
/// persistent user data — bookmarks, history, sessions, feedback, AI models,
/// settings — that an offline attacker could otherwise lift off a stolen device.
///
/// Ephemeral caches (e.g. transient screenshots in `tmp/`) are intentionally
/// left at the system default because they have no long-term threat model;
/// their call sites document the decision inline.
enum FileProtection {
    /// Writes `data` to `url` and tags the file with `NSFileProtectionComplete`.
    ///
    /// Uses `Data.write(to:options:)` with `.completeFileProtection` so the
    /// protection class is applied atomically with the write — there is no
    /// window during which the file exists at a weaker class.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Sets `NSFileProtectionComplete` on an existing file or directory.
    ///
    /// New files created inside a protected directory inherit the parent's
    /// class, so applying this to a directory after `createDirectory` is the
    /// cheapest way to protect everything subsequently written there
    /// (e.g. downloaded AI models, persisted feedback reports).
    static func setComplete(at url: URL) throws {
        var values = URLResourceValues()
        values.fileProtection = .complete
        var mutable = url
        try mutable.setResourceValues(values)
    }
}
