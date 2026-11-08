import Foundation

private final class BrowserResourceAnchor: NSObject {}

/// Resource lookup follows the library's containing bundle, including unhosted tests.
enum KelpieResources {
    static let bundle: Bundle = {
        let owner = Bundle(for: BrowserResourceAnchor.self)
        guard let url = owner.url(forResource: "KelpieBrowserResources", withExtension: "bundle"),
              let bundle = Bundle(url: url) else {
            preconditionFailure("KelpieBrowserResources.bundle must be packaged with the browser library")
        }
        return bundle
    }()
}
