import ProjectDescription
import ProjectDescriptionHelpers

let macBrowser = Target.target(
    name: "KelpieBrowserMac",
    destinations: .macOS,
    product: .staticLibrary,
    bundleId: "com.unlikeotherai.kelpie.browser.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [
        .glob("shared/**/*.swift"),
        .glob("macos/**/*.swift"),
        .glob(KelpieBrowserBuild.webKitOnly ? "macos/AI/**/*.mm" : "macos/**/*.mm")
    ],
    dependencies: [.target(name: "KelpieResourcesMac")],
    settings: .settings(
        base: KelpieBrowserBuild.mac(core: "$(PROJECT_DIR)/..", additional: [
            "DEFINES_MODULE": "YES",
            "PRODUCT_MODULE_NAME": "KelpieBrowser",
            "ENABLE_TESTABILITY": "YES",
            "SWIFT_OBJC_BRIDGING_HEADER": "macos/Kelpie-Bridging-Header.h",
            "COMBINE_HIDPI_IMAGES": "YES",
            "ENABLE_APP_SANDBOX": .string(KelpieBrowserBuild.webKitOnly ? "YES" : "NO")
        ])
    )
)

let iosBrowser = Target.target(
    name: "KelpieBrowserIOS",
    destinations: [.iPhone, .iPad],
    product: .staticLibrary,
    bundleId: "com.unlikeotherai.kelpie.browser.ios",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [
        .glob("shared/**/*.swift"),
        .glob("ios/**/*.swift")
    ],
    dependencies: [.target(name: "KelpieResourcesIOS")],
    settings: .settings(
        base: KelpieBrowserBuild.ios(core: "$(PROJECT_DIR)/..", additional: [
            "DEFINES_MODULE": "YES",
            "PRODUCT_MODULE_NAME": "KelpieBrowser",
            "ENABLE_TESTABILITY": "YES",
            "SWIFT_OBJC_BRIDGING_HEADER": "ios/Kelpie-Bridging-Header.h",
            "TARGETED_DEVICE_FAMILY": "1,2"
        ])
    )
)

let macResources = Target.target(
    name: "KelpieResourcesMac",
    destinations: .macOS,
    product: .bundle,
    bundleId: "com.unlikeotherai.kelpie.browser.resources.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    resources: [.glob(pattern: "shared/BrowserAssets.xcassets"), .glob(pattern: "shared/Resources/**"), .glob(pattern: "../native/licenses/*.txt"), .glob(pattern: "../native/resources/*")],
    settings: .settings(base: ["PRODUCT_NAME": "KelpieBrowserResources"])
)

let iosResources = Target.target(
    name: "KelpieResourcesIOS",
    destinations: [.iPhone, .iPad],
    product: .bundle,
    bundleId: "com.unlikeotherai.kelpie.browser.resources.ios",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    resources: [.glob(pattern: "shared/BrowserAssets.xcassets"), .glob(pattern: "shared/Resources/**"), .glob(pattern: "../native/licenses/*.txt"), .glob(pattern: "../native/resources/*")],
    settings: .settings(base: ["PRODUCT_NAME": "KelpieBrowserResources"])
)

let project = Project(
    name: "KelpieBrowser",
    targets: [macResources, iosResources, macBrowser, iosBrowser]
)
