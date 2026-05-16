import Foundation

struct FeedbackRecord {
    let reportID: String
    let storedAt: String
    let payload: [String: Any]
}

enum FeedbackStore {
    static func save(
        payload body: [String: Any],
        platform: String,
        deviceID: String,
        deviceName: String
    ) throws -> FeedbackRecord {
        let reportID = UUID().uuidString.lowercased()
        let storedAt = ISO8601DateFormatter().string(from: Date())
        let payload = body.merging([
            "reportId": reportID,
            "storedAt": storedAt,
            "platform": platform,
            "deviceId": deviceID,
            "deviceName": deviceName
        ]) { _, new in new }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let directory = feedbackDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Mark the directory NSFileProtectionComplete so any future report
        // inherits the protection class even if a write path forgets to set it.
        try? FileProtection.setComplete(at: directory)
        let file = directory.appendingPathComponent("\(storedAt.replacingOccurrences(of: ":", with: "-"))-\(reportID).json")
        try FileProtection.write(data, to: file)
        return FeedbackRecord(reportID: reportID, storedAt: storedAt, payload: payload)
    }

    private static func feedbackDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Kelpie", isDirectory: true)
            .appendingPathComponent("feedback", isDirectory: true)
    }
}
