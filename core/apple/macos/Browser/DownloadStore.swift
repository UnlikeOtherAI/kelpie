import CryptoKit
import Foundation
import WebKit

/// Every WebKit download in this browser session: page-started (a link or
/// response the site serves as a file) and agent-started (`download`).
///
/// A download runs inside the WKWebView that started it, so it carries that
/// tab's website data store — its cookies and sign-ins, including partitions.
/// Files go to the user's Downloads directory under a unique name. A download
/// is reported `complete` only after the file is on disk with its size and
/// SHA-256; any refusal or interruption is `failed` with a reason, and its
/// partial file is removed.
@MainActor
final class DownloadStore: NSObject, WKDownloadDelegate {
    static let shared = DownloadStore()

    enum Origin: String { case page, agent }
    enum State: String { case inProgress = "in-progress", complete, failed }

    struct Record {
        let id: String
        let url: String
        let tabId: String?
        let origin: Origin
        let startedAt: Date
        var state: State = .inProgress
        var filename: String?
        var path: String?
        var mimeType: String?
        var bytesReceived: Int64 = 0
        var totalBytes: Int64?
        var sha256: String?
        var error: String?
        var finishedAt: Date?
    }

    /// Bounded so a long-running browser does not grow without limit; only
    /// finished records are dropped, oldest first.
    static let recordLimit = 200

    private let directoryProvider: () -> URL
    private let fileManager = FileManager.default
    private var records: [Record] = []
    private var active: [String: WKDownload] = [:]
    private var ids: [ObjectIdentifier: String] = [:]
    private var reserved: Set<String> = []

    init(directory: @escaping () -> URL = DownloadStore.userDownloadsDirectory) {
        directoryProvider = directory
        super.init()
    }

    nonisolated static func userDownloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Tracking

    /// Takes ownership of a download WebKit has just created.
    @discardableResult
    func track(_ download: WKDownload, tabId: String?, origin: Origin) -> Record {
        let record = Record(
            id: UUID().uuidString,
            url: download.originalRequest?.url?.absoluteString ?? "",
            tabId: tabId,
            origin: origin,
            startedAt: Date()
        )
        download.delegate = self
        ids[ObjectIdentifier(download)] = record.id
        active[record.id] = download
        records.append(record)
        trimFinished()
        return record
    }

    func record(id: String) -> Record? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        return refreshedProgress(records[index])
    }

    /// Newest first, with live byte counts for transfers still running.
    func list() -> [Record] {
        records.reversed().map(refreshedProgress)
    }

    // MARK: - WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard let id = ids[ObjectIdentifier(download)] else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode
        if let refusal = DownloadPolicy.refusal(forHTTPStatus: status) {
            // Returning nil cancels the transfer; WebKit then reports the failure.
            update(id) { $0.error = refusal }
            return nil
        }
        let directory = directoryProvider()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            update(id) { $0.error = "Cannot create the downloads directory: \(error.localizedDescription)" }
            return nil
        }
        let destination = DownloadPolicy.uniqueDestination(for: suggestedFilename, in: directory) { candidate in
            reserved.contains(candidate.path) || fileManager.fileExists(atPath: candidate.path)
        }
        reserved.insert(destination.path)
        update(id) {
            $0.filename = destination.lastPathComponent
            $0.path = destination.path
            $0.mimeType = response.mimeType
            $0.totalBytes = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        active.removeValue(forKey: id)
        guard let path = record(id: id)?.path else {
            finish(id, failure: "WebKit finished without a destination")
            return
        }
        Task.detached(priority: .utility) {
            let result = Self.measure(path: path)
            await MainActor.run { self.complete(id, path: path, measurement: result) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        active.removeValue(forKey: id)
        let existing = record(id: id)?.error
        finish(id, failure: existing ?? error.localizedDescription)
    }

    // MARK: - Completion

    private nonisolated static func measure(path: String) -> Result<(size: Int64, sha256: String), Error> {
        Result {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            var hasher = SHA256()
            var size: Int64 = 0
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
                size += Int64(chunk.count)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return (size, digest)
        }
    }

    private func complete(_ id: String, path: String, measurement: Result<(size: Int64, sha256: String), Error>) {
        reserved.remove(path)
        switch measurement {
        case .success(let value):
            update(id) {
                $0.state = .complete
                $0.bytesReceived = value.size
                $0.totalBytes = value.size
                $0.sha256 = value.sha256
                $0.finishedAt = Date()
            }
        case .failure(let error):
            finish(id, failure: "The saved file could not be read: \(error.localizedDescription)")
        }
    }

    /// A failed download never leaves a partial file that looks like a result.
    private func finish(_ id: String, failure: String) {
        guard let current = record(id: id) else { return }
        if let path = current.path {
            reserved.remove(path)
            try? fileManager.removeItem(atPath: path)
        }
        update(id) {
            $0.state = .failed
            $0.error = failure
            $0.path = nil
            $0.finishedAt = Date()
        }
    }

    private func update(_ id: String, _ change: (inout Record) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
    }

    private func refreshedProgress(_ record: Record) -> Record {
        guard record.state == .inProgress, let download = active[record.id] else { return record }
        var live = record
        live.bytesReceived = max(record.bytesReceived, download.progress.completedUnitCount)
        if live.totalBytes == nil, download.progress.totalUnitCount > 0 {
            live.totalBytes = download.progress.totalUnitCount
        }
        return live
    }

    private func trimFinished() {
        var excess = records.count - Self.recordLimit
        guard excess > 0 else { return }
        records.removeAll { record in
            guard excess > 0, record.state != .inProgress else { return false }
            excess -= 1
            return true
        }
    }
}

extension DownloadStore.Record {
    /// The wire shape shared by `download` and `get-downloads`; absent values are JSON null.
    var json: [String: Any] {
        let iso = ISO8601DateFormatter()
        func value(_ optional: Any?) -> Any { optional ?? NSNull() }
        return [
            "id": id,
            "url": url,
            "tabId": value(tabId),
            "origin": origin.rawValue,
            "state": state.rawValue,
            "filename": value(filename),
            "path": value(path),
            "mimeType": value(mimeType),
            "bytesReceived": bytesReceived,
            "totalBytes": value(totalBytes),
            "sha256": value(sha256),
            "error": value(error),
            "startedAt": iso.string(from: startedAt),
            "finishedAt": value(finishedAt.map { iso.string(from: $0) })
        ]
    }
}
