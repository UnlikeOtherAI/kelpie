import Foundation

/// Shared cookie jar persisted under ~/.kelpie so local browser windows and
/// renderer engines can reuse authentication state.
enum SharedCookieJar {
    struct Snapshot {
        let cookies: [HTTPCookie]
        let signature: String
        let modifiedAt: Date?
    }

    private struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
        let isHTTPOnly: Bool
        let isSecure: Bool
        let sameSite: String?

        private enum CodingKeys: String, CodingKey {
            case name, value, domain, path, expires, isHTTPOnly, isSecure, sameSite
        }
    }

    private struct Payload: Codable {
        let updatedAt: Date
        let cookies: [StoredCookie]
    }

    static func load() -> Snapshot {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder.pretty.decode(Payload.self, from: data) else {
            return Snapshot(cookies: [], signature: "", modifiedAt: nil)
        }

        let cookies = payload.cookies.compactMap(makeCookie)
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        return Snapshot(
            cookies: cookies,
            signature: signature(for: cookies),
            modifiedAt: modifiedAt
        )
    }

    static func save(cookies: [HTTPCookie]) {
        let payload = Payload(
            updatedAt: Date(),
            cookies: cookies.map(makeStoredCookie)
        )

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[SharedCookieJar] Failed to save cookies: %@", error.localizedDescription)
        }
    }

    static func signature(for cookies: [HTTPCookie]) -> String {
        cookies
            .map { cookie in
                [
                    cookie.domain,
                    cookie.path,
                    cookie.name,
                    cookie.value,
                    cookie.expiresDate?.timeIntervalSince1970.description ?? "",
                    cookie.isHTTPOnly ? "1" : "0",
                    cookie.isSecure ? "1" : "0",
                    cookie.sameSitePolicy?.rawValue ?? ""
                ].joined(separator: "\u{1F}")
            }
            .sorted()
            .joined(separator: "\u{1E}")
    }

    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kelpie", isDirectory: true)
            .appendingPathComponent("session", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("cookies.json")
    }

    private static func makeStoredCookie(_ cookie: HTTPCookie) -> StoredCookie {
        StoredCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expires: cookie.expiresDate,
            isHTTPOnly: cookie.isHTTPOnly,
            isSecure: cookie.isSecure,
            sameSite: cookie.sameSitePolicy?.rawValue
        )
    }

    private static func makeCookie(_ stored: StoredCookie) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: stored.name,
            .value: stored.value,
            .domain: stored.domain,
            .path: stored.path
        ]
        if let expires = stored.expires {
            properties[.expires] = expires
        }
        if stored.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if stored.isSecure {
            properties[.secure] = "TRUE"
        }
        if let sameSite = stored.sameSite {
            properties[HTTPCookiePropertyKey("SameSite")] = sameSite
        }
        return HTTPCookie(properties: properties)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pretty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
