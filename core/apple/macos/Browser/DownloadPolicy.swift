import Foundation

/// Pure rules for which responses become downloads and where they are saved.
/// Kept free of WebKit so the decisions are unit-testable without a renderer.
enum DownloadPolicy {
    /// A response is saved instead of shown when the site marks it as an
    /// attachment or WebKit cannot render its MIME type (zip, dmg, binary).
    /// Inline PDFs and images keep rendering, as in Safari.
    static func shouldDownload(canShowMIMEType: Bool, contentDisposition: String?) -> Bool {
        isAttachment(contentDisposition) || !canShowMIMEType
    }

    /// RFC 6266: the disposition type is the first token, case-insensitive.
    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let contentDisposition else { return false }
        let type = contentDisposition.split(separator: ";", maxSplits: 1).first ?? ""
        return type.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
    }

    /// A single path component that cannot escape the downloads directory or
    /// hide itself. Falls back to `download` when nothing usable remains.
    static func sanitizedFilename(_ suggested: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        let cleaned = suggested.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .map { forbidden.contains($0) ? "_" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let visible = String(cleaned.drop(while: { $0 == "." }))
        let bounded = String(visible.prefix(200))
        return bounded.isEmpty ? "download" : bounded
    }

    /// First free name in `directory`, Finder style: `name.zip`, `name (1).zip`, ...
    /// `isTaken` covers both existing files and destinations reserved by
    /// downloads that have not written their first byte yet.
    static func uniqueDestination(
        for suggested: String,
        in directory: URL,
        isTaken: (URL) -> Bool
    ) -> URL {
        let name = sanitizedFilename(suggested)
        let candidate = directory.appendingPathComponent(name, isDirectory: false)
        guard isTaken(candidate) else { return candidate }
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var index = 1
        while true {
            let numbered = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let url = directory.appendingPathComponent(numbered, isDirectory: false)
            if !isTaken(url) { return url }
            index += 1
        }
    }

    /// Only an HTTP error status refuses the body; anything else is the file.
    static func refusal(forHTTPStatus status: Int?) -> String? {
        guard let status, status >= 400 else { return nil }
        return "HTTP \(status)"
    }
}
