import AppKit

/// Extracts a page favicon using JS, then fetches and decodes it.
/// On failure, returns nil — callers show a letter avatar instead.
enum FaviconExtractor {
    static func extract(from renderer: any RendererEngine, completion: @escaping (NSImage?) -> Void) {
        Task { @MainActor in
            let result = try? await renderer.evaluateJS(faviconScript)
            guard let urlString = result as? String, !urlString.isEmpty,
                  let faviconURL = URL(string: urlString) else {
                completion(nil)
                return
            }
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: faviconURL)
                    let image = Self.decodeImage(data: data, response: response, url: faviconURL)
                    await MainActor.run { completion(image) }
                } catch {
                    await MainActor.run { completion(nil) }
                }
            }
        }
    }

    /// NSImage(data:) silently returns nil for SVG payloads. Writing to a
    /// temp file with the correct extension lets NSImage pick the right decoder.
    private static func decodeImage(data: Data, response: URLResponse, url: URL) -> NSImage? {
        let isSVG = (response as? HTTPURLResponse)?.mimeType?.contains("svg") == true
            || url.pathExtension.lowercased() == "svg"
        if isSVG {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".svg")
            do {
                try data.write(to: tmp)
                let img = NSImage(contentsOf: tmp)
                try? FileManager.default.removeItem(at: tmp)
                return img
            } catch {
                return nil
            }
        }
        return NSImage(data: data)
    }

    private static let faviconScript = """
    (function() {
        var link = document.querySelector('link[rel~="icon"]');
        if (link && link.href) return link.href;
        var apple = document.querySelector('link[rel="apple-touch-icon"]');
        if (apple && apple.href) return apple.href;
        return window.location.protocol + '//' + window.location.host + '/favicon.ico';
    })()
    """
}
