import Foundation

/// The browser's assets travel with the library rather than the containing app's UI.
enum KelpieResources {
    static let bundle: Bundle? = Bundle.main.url(forResource: "KelpieBrowserResources", withExtension: "bundle")
        .flatMap { Bundle(url: $0) }
}
