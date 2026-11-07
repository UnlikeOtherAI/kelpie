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
        try FileManager.default.createDirectory(at: feedbackDirectory(), withIntermediateDirectories: true)
        try data.write(to: feedbackDirectory().appendingPathComponent("\(storedAt.replacingOccurrences(of: ":", with: "-"))-\(reportID).json"))
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
