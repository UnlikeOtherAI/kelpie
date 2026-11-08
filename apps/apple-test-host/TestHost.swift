import SwiftUI

/// A native application lifecycle for library tests, without the standalone browser's account or service startup.
@main
struct KelpieLibraryTestHost: App {
    var body: some Scene {
        WindowGroup { Color.clear }
    }
}
