import Foundation

/// A delayed handler keeps only the authority of the job that created it.
struct ConnectAuthorization {
    let jobID: String
    let attemptID: String
    let deadline: Date

    init?(_ command: [String: Any]) {
        guard let jobID = command["jobId"] as? String,
              let attemptID = command["attemptId"] as? String,
              let raw = command["deadline"] as? String,
              let deadline = Self.parseDeadline(raw) else { return nil }
        self.jobID = jobID
        self.attemptID = attemptID
        self.deadline = deadline
    }

    func matches(_ current: [String: Any]?, now: Date = Date()) -> Bool {
        current?["jobId"] as? String == jobID && current?["attemptId"] as? String == attemptID && deadline > now
    }

    static func parseDeadline(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
