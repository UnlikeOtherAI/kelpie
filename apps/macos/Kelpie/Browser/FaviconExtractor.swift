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
                    let (data, _) = try await URLSession.shared.data(from: faviconURL)
                    let image = NSImage(data: data)
                    await MainActor.run { completion(image) }
                } catch {
                    await MainActor.run { completion(nil) }
                }
            }
        }
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
