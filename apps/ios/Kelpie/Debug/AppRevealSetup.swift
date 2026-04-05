// AppReveal integration for debug builds.
// To enable: add AppReveal as an SPM dependency, then add APPREVEAL_ENABLED
// to Swift Active Compilation Conditions in build settings.
// SPM: clone https://github.com/UnlikeOtherAI/AppReveal.git, add iOS/ as local package.

#if DEBUG && APPREVEAL_ENABLED
import AppReveal

enum AppRevealSetup {
    @MainActor
    static func configure() {
        AppReveal.start()
    }
}
#else
enum AppRevealSetup {
    static func configure() {
        // AppReveal not linked — no-op
    }
}
#endif
