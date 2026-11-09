import Foundation

struct AppRelease: Decodable, Equatable {
    let target: String
    let version: String
    let url: URL
    let sha256: String?

    static func version(_ value: String) -> [Int]? {
        guard value.range(of: #"^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value.split(separator: ".").compactMap { Int($0) }
    }

    static func allowedURL(_ url: URL, target: String) -> Bool {
        let text = url.absoluteString
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !text.contains("\\"), !text.contains("..") else { return false }
        if target != "ios", text.hasPrefix("https://github.com/UnlikeOtherAI/kelpie/releases/download/"),
           text.rangeOfCharacter(from: CharacterSet(charactersIn: "?#%")) == nil { return true }
        return target == "ios" && text.range(
            of: #"^https://apps\.apple\.com/([a-z]{2}/)?app/([a-zA-Z0-9-]+/)?id[0-9]+$"#,
            options: .regularExpression) != nil
    }

    static func newest(in data: Data, target: String, installed: String) -> Self? {
        guard let current = version(installed),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var newest: Self?
        let marker = "<!-- kelpie-update: "
        for entry in entries {
            guard let draft = entry["draft"] as? Bool, !draft,
                  let prerelease = entry["prerelease"] as? Bool, !prerelease,
                  let notes = entry["body"] as? String else { continue }
            for part in notes.components(separatedBy: marker).dropFirst() {
                guard let end = part.range(of: " -->"),
                      let item = try? JSONDecoder().decode(Self.self, from: Data(part[..<end.lowerBound].utf8)),
                      item.target == target, let candidate = version(item.version),
                      current.lexicographicallyPrecedes(candidate), allowedURL(item.url, target: target) else { continue }
                if target != "ios" {
                    guard let hash = item.sha256,
                          hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { continue }
                }
                if let existing = newest, let previous = version(existing.version),
                   !previous.lexicographicallyPrecedes(candidate) { continue }
                newest = item
            }
        }
        return newest
    }
}
