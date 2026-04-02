import Foundation

struct PageSummary {
    let title: String
    let url: String
    let wordCount: Int
    let formCount: Int
    let errorCount: Int
    let consoleCount: Int
    let networkRequestCount: Int
    let linkCount: Int
    let interactiveElementCount: Int

    func formatted() -> String {
        """
        Page: "\(title)"
        URL: \(url)
        Words: \(wordCount)
        Forms: \(formCount)
        JS Errors: \(errorCount)
        Console: \(consoleCount) messages
        Network: \(networkRequestCount) requests
        Links: \(linkCount)
        Interactive elements: \(interactiveElementCount)
        """
    }

    @MainActor
    static func gather(from context: HandlerContext) async -> PageSummary {
        let counts = (try? await context.evaluateJSReturningJSON(
            """
            (function() {
                var root = document.body || document.documentElement;
                var text = (root?.innerText || root?.textContent || '').trim();
                var interactive = document.querySelectorAll(
                    'a,button,input,select,textarea,[role="button"],[role="link"]'
                ).length;
                var resources = performance.getEntriesByType('resource').length +
                    performance.getEntriesByType('navigation').length;
                return {
                    title: document.title || '',
                    url: location.href || '',
                    wordCount: text ? text.split(/\\s+/).length : 0,
                    formCount: document.forms.length,
                    networkRequestCount: resources,
                    linkCount: document.querySelectorAll('a[href]').length,
                    interactiveElementCount: interactive
                };
            })()
            """
        )) ?? [:]

        let errors = context.consoleMessages.filter { ($0["level"] as? String) == "error" }.count

        return PageSummary(
            title: counts["title"] as? String ?? context.currentTitle,
            url: counts["url"] as? String ?? context.currentURL?.absoluteString ?? "",
            wordCount: counts["wordCount"] as? Int ?? 0,
            formCount: counts["formCount"] as? Int ?? 0,
            errorCount: errors,
            consoleCount: context.consoleMessages.count,
            networkRequestCount: counts["networkRequestCount"] as? Int ?? 0,
            linkCount: counts["linkCount"] as? Int ?? 0,
            interactiveElementCount: counts["interactiveElementCount"] as? Int ?? 0
        )
    }
}
