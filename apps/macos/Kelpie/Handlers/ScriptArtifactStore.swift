import CoreFoundation
import CryptoKit
import Foundation

/// Private, bounded, expiring files. Only authenticated run owners receive byte chunks.
@MainActor
final class ScriptArtifactStore {
    static let shared = ScriptArtifactStore()
    private struct Entry {
        let runID: String
        let owner: String
        let url: URL
        let manifest: [String: Any]
        let created = Date()
    }
    private var entries: [String: Entry] = [:]
    private let maximumBytes = 256 * 1024 * 1024
    private let maximumAge: TimeInterval = 3600

    func add(url: URL, runID: String, mimeType: String, owner: String, extra: [String: Any] = [:]) throws -> [String: Any] {
        expire()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteLength = 0
        while let data = try handle.read(upToCount: 65536), !data.isEmpty {
            byteLength += data.count
            guard byteLength <= maximumBytes else { throw ScriptCaptureError.budget }
            hasher.update(data: data)
        }
        guard byteLength > 0, ["image/png", "image/gif", "video/mp4"].contains(mimeType),
              !runID.isEmpty, runID.count <= 128, !owner.isEmpty,
              extra["partial"] == nil || extra["partial"] is Bool else { throw ScriptCaptureError.image }
        let artifactID = UUID().uuidString
        var manifest = extra
        manifest["id"] = artifactID
        manifest["partial"] = extra["partial"] as? Bool ?? false
        manifest["mimeType"] = mimeType
        manifest["byteLength"] = byteLength
        manifest["sha256"] = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        entries[artifactID] = Entry(runID: runID, owner: owner, url: url, manifest: manifest)
        trimToBudget()
        return manifest
    }

    /// The caller supplies blockedRunID only after matching the active run owner.
    func read(_ body: [String: Any], owner: String, blockedRunID: String? = nil) -> [String: Any] {
        expire()
        let keys: Set<String> = ["runId", "artifactId", "offset", "length"]
        guard Set(body.keys).isSubset(of: keys),
              let runID = body["runId"] as? String, !runID.isEmpty, runID.count <= 128,
              let artifactID = body["artifactId"] as? String, !artifactID.isEmpty, artifactID.count <= 128,
              let offset = Self.integer(body["offset"], default: 0),
              let length = Self.integer(body["length"], default: 262144),
              offset >= 0, length > 0, length <= 1048576 else {
            return errorResponse(code: "INVALID_PARAM", message: "Invalid artifact request or range")
        }
        if runID == blockedRunID {
            return errorResponse(code: "ARTIFACT_NOT_READY", message: "Artifact decision is not terminal")
        }
        guard let entry = entries[artifactID], entry.runID == runID, entry.owner == owner else {
            return errorResponse(code: "ARTIFACT_NOT_FOUND", message: "Artifact expired or does not belong to this run")
        }
        let byteLength = entry.manifest["byteLength"] as? Int ?? 0
        guard offset <= byteLength else {
            return errorResponse(code: "INVALID_PARAM", message: "Artifact offset exceeds its size")
        }
        do {
            let handle = try FileHandle(forReadingFrom: entry.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: min(length, byteLength - offset)) ?? Data()
            guard data.count == min(length, byteLength - offset) else {
                return errorResponse(code: "ARTIFACT_READ_FAILED", message: "Artifact bytes are unavailable")
            }
            return successResponse([
                "runId": runID, "artifactId": artifactID,
                "mimeType": entry.manifest["mimeType"] ?? "",
                "byteLength": byteLength, "sha256": entry.manifest["sha256"] ?? "",
                "data": data.base64EncodedString(), "offset": offset,
                "nextOffset": offset + data.count, "eof": offset + data.count == byteLength
            ])
        } catch {
            return errorResponse(code: "ARTIFACT_READ_FAILED", message: "Artifact bytes are unavailable")
        }
    }

    private static func integer(_ value: Any?, default fallback: Int) -> Int? {
        guard let value else { return fallback }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(Int.max - 1024) else { return nil }
        return number.intValue
    }

    private func expire() {
        for (key, entry) in entries where Date().timeIntervalSince(entry.created) > maximumAge {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
        }
    }

    private func trimToBudget() {
        var total = entries.values.reduce(0) { $0 + ($1.manifest["byteLength"] as? Int ?? 0) }
        for (key, entry) in entries.sorted(by: { $0.value.created < $1.value.created }) where total > maximumBytes {
            total -= entry.manifest["byteLength"] as? Int ?? 0
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: key)
        }
    }
}
