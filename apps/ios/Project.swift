import ProjectDescription

// MARK: - Linker flags

let iOSLinkerFlags: SettingValue = .array([
    "-lkelpie_core_state",
    "-lkelpie_core_protocol",
    "-lkelpie_core_automation",
    "-lkelpie_core_mcp",
    "-lkelpie_core_ai",
    "-framework AppIntents",
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
    sources: [
        .glob("Kelpie/**/*.swift"),
        // Shared from macOS — cross-project source references
        .glob("../macos/Kelpie/Handlers/Snapshot3DBridge.swift"),
    ],
    resources: [
        .glob(pattern: "Kelpie/Assets.xcassets"),
    ],
    dependencies: [
        .package(product: "AppReveal"),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "SWIFT_OBJC_BRIDGING_HEADER": "Kelpie/Kelpie-Bridging-Header.h",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/../../native/core-state/include",
                "$(PROJECT_DIR)/../../native/core-protocol/include",
                "$(PROJECT_DIR)/../../native/core-automation/include",
                "$(PROJECT_DIR)/../../native/core-mcp/include",
                "$(PROJECT_DIR)/../../native/core-ai/include",
            ]),
            "LIBRARY_SEARCH_PATHS": .array([
                "$(KELPIE_NATIVE_BUILD_DIR)/core-state",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-protocol",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-automation",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-mcp",
                "$(KELPIE_NATIVE_BUILD_DIR)/core-ai",
            ]),
            "OTHER_LDFLAGS": iOSLinkerFlags,
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO",
            "MARKETING_VERSION": "0.1.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "DEVELOPMENT_TEAM": "G42HP8BM2N",
            // Conditional native build dir — device vs simulator
            "KELPIE_NATIVE_BUILD_DIR": "$(PROJECT_DIR)/../../native/.build-iphoneos",
            "KELPIE_NATIVE_BUILD_DIR[sdk=iphonesimulator*]": "$(PROJECT_DIR)/../../native/.build-ios-sim",
        ]
    )
)

// MARK: - Project

let project = Project(
    name: "Kelpie",
    packages: [
        .local(path: "../../vendor/AppReveal/iOS"),
    ],
    targets: [
        kelpieApp,
    ]
)
