import Foundation

// CEF dispatches download callbacks on the main thread on macOS.
@MainActor
@_cdecl("KelpieBeginChromiumDownload")
func beginChromiumDownload(
    _ browser: Int32,
    _ item: UInt32,
    _ url: UnsafePointer<CChar>,
    _ name: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>? {
    let file = DownloadStore.shared.beginChromium(
        id: "cef-\(browser)-\(item)",
        url: String(cString: url),
        suggestedName: String(cString: name)
    )
    return file.flatMap { strdup($0.path) }
}

@MainActor
@_cdecl("KelpieUpdateChromiumDownload")
func updateChromiumDownload(
    _ browser: Int32,
    _ item: UInt32,
    _ received: Int64,
    _ total: Int64,
    _ complete: Int32,
    _ interrupted: Int32
) {
    DownloadStore.shared.updateChromium(
        id: "cef-\(browser)-\(item)",
        received: received,
        total: total,
        complete: complete != 0,
        interrupted: interrupted != 0
    )
}
