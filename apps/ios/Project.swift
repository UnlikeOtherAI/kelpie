import ProjectDescription
import ProjectDescriptionHelpers

// MARK: - Target


let kelpieApp = Target.target(
    name: "Kelpie",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.unlikeotherai.kelpie",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .file(path: "Kelpie/Info.plist"),
    sources: [.glob("Kelpie/**/*.swift"), .glob("../updates/apple/**/*.swift")],
    resources: [
        .glob(pattern: "Kelpie/Assets.xcassets"),
    ],
    dependencies: [
        .project(target: "KelpieBrowserIOS", path: "../../core/apple"),
        .package(product: "AppReveal"),
    ],
    settings: .settings(
        base: KelpieBrowserBuild.ios(core: "$(PROJECT_DIR)/../../core", additional: [
            "MARKETING_VERSION": "0.2.1",
            "CURRENT_PROJECT_VERSION": "23",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "DEVELOPMENT_TEAM": "59S95D279D"
        ])
    )
)


let kelpieEmbeddingHost = Target.target(
    name: "KelpieEmbeddingHost",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.unlikeotherai.kelpie.embeddingverify.ios",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .extendingDefault(with: [
        "NSLocalNetworkUsageDescription": "Inspect the local embedding verification host.",
        "NSBonjourServices": ["_appreveal._tcp"]
    ]),
    sources: [.glob("../apple-embedding-host/ios/**/*.swift")],
    dependencies: [
        .project(target: "KelpieBrowserIOS", path: "../../core/apple"),
        .package(product: "AppReveal")
    ],
    settings: .settings(base: KelpieBrowserBuild.ios(core: "$(PROJECT_DIR)/../../core"))
)


let kelpieEmbeddingUITests = Target.target(
    name: "KelpieEmbeddingUITests",
    destinations: [.iPhone, .iPad],
    product: .uiTests,
    bundleId: "com.unlikeotherai.kelpie.embeddingverify.ios.uitests",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [.glob("../apple-embedding-host/UITests/**/*.swift")],
    dependencies: [.target(name: "KelpieEmbeddingHost")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieLibraryTestHost = Target.target(
    name: "KelpieLibraryTestHost",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.unlikeotherai.kelpie.tests.ios.host",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [.glob("../apple-test-host/**/*.swift")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieUpdateTests = Target.target(
    name: "KelpieUpdateTestsIOS",
    destinations: [.iPhone, .iPad],
    product: .unitTests,
    bundleId: "com.unlikeotherai.kelpie.updates.tests.ios",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [.glob("../updates/apple/**/*.swift"), .glob("../updates/tests/ReleaseFeedTests.swift")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieTests = Target.target(
    name: "KelpieTests",
    destinations: [.iPhone, .iPad],
    product: .unitTests,
    bundleId: "com.unlikeotherai.kelpie.tests",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [
        .glob("Tests/**/*.swift"),
        .glob("../macos/Tests/UOAAccountTests.swift"),
        .glob("../macos/Tests/NetworkTrafficStoreTests.swift"),
        .glob("../macos/Tests/FavouritesTreeTests.swift"),
        .glob("../macos/Tests/UOASessionTests.swift"),
        .glob("../macos/Tests/HostSessionTests.swift"),
        .glob("../macos/Tests/ConnectAuthorizationTests.swift"),
        .glob("../macos/Tests/ConnectScreenshotBudgetTests.swift"),
        .glob("../macos/Tests/OpenAICompatible/**/*.swift"),
        .glob("../macos/Tests/BrowserControlGatewayTests.swift"),
        .glob("../macos/Tests/RealWebKitBrowserControlTests.swift"),
    ],
    dependencies: [
        .target(name: "KelpieLibraryTestHost"),
        .project(target: "KelpieBrowserIOS", path: "../../core/apple"),
    ],
    settings: .settings(
        base: KelpieBrowserBuild.ios(core: "$(PROJECT_DIR)/../../core")
    )
)

// MARK: - Schemes

let kelpieUITests = Target.target(
    name: "KelpieUITests",
    destinations: [.iPhone, .iPad],
    product: .uiTests,
    bundleId: "com.unlikeotherai.kelpie.uitests",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    sources: [.glob("UITests/**/*.swift")],
    dependencies: [.target(name: "Kelpie")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieScheme = Scheme.scheme(
    name: "Kelpie",
    shared: true,
    buildAction: .buildAction(targets: ["Kelpie"]),
    testAction: .targets(["KelpieTests", "KelpieUpdateTestsIOS", "KelpieUITests"])
)

// MARK: - Project

let project = Project(
    name: "Kelpie",
    packages: [
        .local(path: "../../vendor/AppReveal/iOS"),
    ],
    targets: [
        kelpieApp,
        kelpieLibraryTestHost,
        kelpieEmbeddingHost,
        kelpieEmbeddingUITests,
        kelpieTests,
        kelpieUpdateTests,
        kelpieUITests,
    ],
    schemes: [
        .scheme(name: "KelpieUpdatesIOS", shared: true,
                buildAction: .buildAction(targets: ["Kelpie"]),
                testAction: .targets(["KelpieUpdateTestsIOS", "KelpieUITests"])),
        .scheme(name: "KelpieUpdateTestsIOS", shared: true,
                buildAction: .buildAction(targets: ["KelpieUpdateTestsIOS"]),
                testAction: .targets(["KelpieUpdateTestsIOS"])),
        kelpieScheme,
        .scheme(name: "KelpieEmbeddingHost", shared: true,
                buildAction: .buildAction(targets: ["KelpieEmbeddingHost"]),
                testAction: .targets(["KelpieEmbeddingUITests"])),
    ]
)
