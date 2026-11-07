import ProjectDescription

let macOSLinkerFlags: SettingValue = .array([
    "-lkelpie_core_state",
    "-lkelpie_core_connect",
    "-lkelpie_core_protocol",
    "-lkelpie_core_automation",
    "-lkelpie_core_mcp",
    "-lkelpie_core_ai",
    "-lllama",
    "-lggml",
    "-lggml-base",
    "-lggml-cpu",
    "-lggml-metal",
    "-lggml-blas",
    "-lc++",
    "-framework AppIntents",
    "-framework Metal",
    "-framework Accelerate",
    "-framework \"Chromium Embedded Framework\"",
])

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
        .glob("macos/**/*.mm"),
    ],
    dependencies: [.target(name: "KelpieResourcesMac")],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "DEFINES_MODULE": "YES",
            "PRODUCT_MODULE_NAME": "KelpieBrowser",
            "ENABLE_TESTABILITY": "YES",
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
            "SWIFT_OBJC_BRIDGING_HEADER": "macos/Kelpie-Bridging-Header.h",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/macos/Renderer",
                "$(PROJECT_DIR)/../../core/native/core-state/include",
                "$(PROJECT_DIR)/../../core/native/core-connect/include",
                "$(PROJECT_DIR)/../../core/native/core-protocol/include",
                "$(PROJECT_DIR)/../../core/native/core-automation/include",
                "$(PROJECT_DIR)/../../core/native/core-mcp/include",
                "$(PROJECT_DIR)/../../core/native/core-ai/include",
                "$(PROJECT_DIR)/macos/Frameworks/cef_include",
                "$(PROJECT_DIR)/macos/vendor/llama.cpp/include",
            ]),
            "LIBRARY_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/../../core/native/.build/core-state",
                "$(PROJECT_DIR)/../../core/native/.build/core-connect",
                "$(PROJECT_DIR)/../../core/native/.build/core-protocol",
                "$(PROJECT_DIR)/../../core/native/.build/core-automation",
                "$(PROJECT_DIR)/../../core/native/.build/core-mcp",
                "$(PROJECT_DIR)/../../core/native/.build/core-ai",
                "$(PROJECT_DIR)/macos/vendor/llama.cpp/lib",
            ]),
            "FRAMEWORK_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/macos/Frameworks",
            ]),
            "OTHER_LDFLAGS": macOSLinkerFlags,
            "COMBINE_HIDPI_IMAGES": "YES",
            "ENABLE_APP_SANDBOX": "NO",
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO",
        ]
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
        .glob("ios/**/*.swift"),
    ],
    dependencies: [.target(name: "KelpieResourcesIOS")],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "DEFINES_MODULE": "YES",
            "PRODUCT_MODULE_NAME": "KelpieBrowser",
            "ENABLE_TESTABILITY": "YES",
            "SWIFT_OBJC_BRIDGING_HEADER": "ios/Kelpie-Bridging-Header.h",
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

let kelpieHelper = Target.target(
    name: "KelpieHelper",
    destinations: .macOS,
    product: .commandLineTool,
    bundleId: "com.kelpie.browser.helper",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .file(path: "Helpers/Info.plist"),
    sources: [
        .glob("Helpers/**/*.mm"),
    ],
    entitlements: .file(path: "Helpers/KelpieHelper.entitlements"),
    settings: .settings(
        base: [
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/macos/Frameworks/cef_include",
            ]),
            "FRAMEWORK_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/macos/Frameworks",
            ]),
            "OTHER_LDFLAGS": .array([
                "-framework \"Chromium Embedded Framework\"",
                "-lc++",
            ]),
        ]
    )
)

let macResources = Target.target(
    name: "KelpieResourcesMac", destinations: .macOS, product: .bundle,
    bundleId: "com.unlikeotherai.kelpie.browser.resources.macos", deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    resources: [.glob(pattern: "shared/Resources/**"), .glob(pattern: "../native/licenses/*.txt"), .glob(pattern: "../native/resources/*")],
    settings: .settings(base: ["PRODUCT_NAME": "KelpieBrowserResources"])
)

let iosResources = Target.target(
    name: "KelpieResourcesIOS", destinations: [.iPhone, .iPad], product: .bundle,
    bundleId: "com.unlikeotherai.kelpie.browser.resources.ios", deploymentTargets: .iOS("16.0"),
    infoPlist: .default,
    resources: [.glob(pattern: "shared/Resources/**"), .glob(pattern: "../native/licenses/*.txt"), .glob(pattern: "../native/resources/*")],
    settings: .settings(base: ["PRODUCT_NAME": "KelpieBrowserResources"])
)

let project = Project(
    name: "KelpieBrowser",
    targets: [macResources, iosResources, macBrowser, iosBrowser, kelpieHelper]
)
