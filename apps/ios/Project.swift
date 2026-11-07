import ProjectDescription

// MARK: - Linker flags

let iOSLinkerFlags: SettingValue = .array([
    "-lkelpie_core_state",
    "-lkelpie_core_connect",
    "-lkelpie_core_protocol",
    "-lkelpie_core_automation",
    "-lkelpie_core_mcp",
    "-lkelpie_core_ai",
    "-lllama", "-lggml", "-lggml-base", "-lggml-cpu",
    "-framework AppIntents",
    "-framework Accelerate",
    "-lc++",
])

// MARK: - Target


let kelpieApp = Target.target(
    name: "Kelpie",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.unlikeotherai.kelpie",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .file(path: "Kelpie/Info.plist"),
    sources: [.glob("Kelpie/**/*.swift")],
    resources: [
        .glob(pattern: "Kelpie/Assets.xcassets"),
    ],
    dependencies: [
        .project(target: "KelpieBrowserIOS", path: "../../core/apple"),
        .package(product: "AppReveal"),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/../../core/native/core-state/include",
                "$(PROJECT_DIR)/../../core/native/core-connect/include",
                "$(PROJECT_DIR)/../../core/native/core-protocol/include",
                "$(PROJECT_DIR)/../../core/native/core-automation/include",
                "$(PROJECT_DIR)/../../core/native/core-mcp/include",
                "$(PROJECT_DIR)/../../core/native/core-ai/include",
            ]),
            "LIBRARY_SEARCH_PATHS": .array([
                "$(KELPIE_NATIVE_BUILD_DIR)/core-state",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-connect",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-protocol",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-automation",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-mcp",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-ai",
                "$(KELPIE_NATIVE_BUILD_DIR)/_deps/kelpie_llama-build/src",
                "$(KELPIE_NATIVE_BUILD_DIR)/_deps/kelpie_llama-build/ggml/src",
                "$(KELPIE_NATIVE_BUILD_DIR)/_deps/kelpie_llama-build/ggml/src/ggml-cpu",
            ]),
            "OTHER_LDFLAGS": iOSLinkerFlags,
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO",
            "MARKETING_VERSION": "0.1.22",
            "CURRENT_PROJECT_VERSION": "21",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "DEVELOPMENT_TEAM": "59S95D279D",
            // Conditional native build dir — device vs simulator
            "KELPIE_NATIVE_BUILD_DIR": "$(PROJECT_DIR)/../../core/native/.build-iphoneos",
            "KELPIE_NATIVE_BUILD_DIR[sdk=iphonesimulator*]": "$(PROJECT_DIR)/../../core/native/.build-ios-sim",
        ]
    )
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
        .glob("../macos/Tests/ConnectAuthorizationTests.swift"),
        .glob("../macos/Tests/ConnectScreenshotBudgetTests.swift"),
        .glob("../macos/Tests/OpenAICompatible/**/*.swift"),
        .glob("../macos/Tests/BrowserControlGatewayTests.swift"),
        .glob("../macos/Tests/RealWebKitBrowserControlTests.swift"),
    ],
    dependencies: [
        .target(name: "Kelpie"),
        .project(target: "KelpieBrowserIOS", path: "../../core/apple"),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
        ]
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
    testAction: .targets(["KelpieTests", "KelpieUITests"])
)

// MARK: - Project

let project = Project(
    name: "Kelpie",
    packages: [
        .local(path: "../../vendor/AppReveal/iOS"),
    ],
    targets: [
        kelpieApp,
        kelpieTests,
        kelpieUITests,
    ],
    schemes: [
        kelpieScheme,
    ]
)
