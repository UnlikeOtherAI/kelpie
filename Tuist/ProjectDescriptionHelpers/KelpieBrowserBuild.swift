import ProjectDescription

/// Link settings for the complete browser library and its existing native core.
public enum KelpieBrowserBuild {
    public static var webKitOnly: Bool { Environment.kelpieWebkitOnly.getBoolean(default: false) }

    /// Tuist does not place transitive resource bundles in a macOS app's Resources phase.
    public static var embedMacResources: TargetScript {
        .post(
            script: """
            SOURCE="${BUILT_PRODUCTS_DIR:?}/KelpieBrowserResources.bundle"
            DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/KelpieBrowserResources.bundle"
            test -d "$SOURCE"
            mkdir -p "$(dirname "$DEST")"
            rm -rf "$DEST"
            ditto "$SOURCE" "$DEST"
            """,
            name: "Embed Kelpie browser resources",
            basedOnDependencyAnalysis: false
        )
    }

    /// The containing project owns the subprocess executable and its packaging.
    public static func cefHelper(core: String) -> Target {
        .target(
            name: "KelpieHelper",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.kelpie.browser.helper",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: .relativeToManifest(core + "/apple/Helpers/Info.plist")),
            sources: [.glob(.relativeToManifest(core + "/apple/Helpers/**/*.mm"))],
            entitlements: .file(path: .relativeToManifest(core + "/apple/Helpers/KelpieHelper.entitlements")),
            settings: .settings(base: [
                "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
                "HEADER_SEARCH_PATHS": .array(["$(PROJECT_DIR)/" + core + "/apple/macos/Frameworks/cef_include"]),
                "FRAMEWORK_SEARCH_PATHS": .array(["$(PROJECT_DIR)/" + core + "/apple/macos/Frameworks"]),
                "OTHER_LDFLAGS": .array(["-framework \"Chromium Embedded Framework\"", "-lc++"])
            ])
        )
    }

    private static let nativeModules = [
        "state", "connect", "protocol", "automation", "mcp", "ai"
    ]

    public static func mac(core: String, additional: SettingsDictionary = [:]) -> SettingsDictionary {
        let native = core + "/native"
        let apple = core + "/apple/macos"
        let flags = nativeModules.map { "-lkelpie_core_" + $0 } + [
            "-lllama", "-lggml", "-lggml-base", "-lggml-cpu", "-lggml-metal", "-lggml-blas",
            "-ObjC", "-lc++", "-framework AppIntents", "-framework Metal", "-framework Accelerate"
        ] + (webKitOnly ? [] : ["-framework \"Chromium Embedded Framework\""])
        var settings: SettingsDictionary = [
            "SWIFT_VERSION": "5.0",
            "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
            "SWIFT_INCLUDE_PATHS": .array([core + "/apple/Native"]),
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
            "HEADER_SEARCH_PATHS": .array(nativeModules.map { native + "/core-" + $0 + "/include" } + [
                apple + "/Renderer", apple + "/Frameworks/cef_include", apple + "/vendor/llama.cpp/include"
            ]),
            "LIBRARY_SEARCH_PATHS": .array(nativeModules.map { native + "/.build/core-" + $0 } + [
                apple + "/vendor/llama.cpp/lib"
            ]),
            "FRAMEWORK_SEARCH_PATHS": .array([apple + "/Frameworks"]),
            "OTHER_LDFLAGS": .array(flags),
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO"
        ]
        if webKitOnly {
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) KELPIE_WEBKIT_ONLY"
            settings["GCC_PREPROCESSOR_DEFINITIONS"] = "$(inherited) KELPIE_WEBKIT_ONLY=1"
        }
        return settings.merging(additional) { _, value in value }
    }

    public static func ios(core: String, additional: SettingsDictionary = [:]) -> SettingsDictionary {
        let native = core + "/native"
        let build = "$(KELPIE_NATIVE_BUILD_DIR)"
        let flags = nativeModules.map { "-lkelpie_core_" + $0 } + [
            "-lllama", "-lggml", "-lggml-base", "-lggml-cpu",
            "-framework AppIntents", "-framework Accelerate", "-lc++"
        ]
        let settings: SettingsDictionary = [
            "SWIFT_VERSION": "5.0",
            "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
            "SWIFT_INCLUDE_PATHS": .array([core + "/apple/Native"]),
            "HEADER_SEARCH_PATHS": .array(nativeModules.map { native + "/core-" + $0 + "/include" }),
            "LIBRARY_SEARCH_PATHS": .array(nativeModules.map { build + "/core-" + $0 } + [
                build + "/_deps/kelpie_llama-build/src",
                build + "/_deps/kelpie_llama-build/ggml/src",
                build + "/_deps/kelpie_llama-build/ggml/src/ggml-cpu"
            ]),
            "OTHER_LDFLAGS": .array(flags),
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO",
            "KELPIE_NATIVE_BUILD_DIR": .string(native + "/.build-iphoneos"),
            "KELPIE_NATIVE_BUILD_DIR[sdk=iphonesimulator*]": .string(native + "/.build-ios-sim")
        ]
        return settings.merging(additional) { _, value in value }
    }
}
