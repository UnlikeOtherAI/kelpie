import Foundation
import ProjectDescription

/// Link settings for the complete browser library and its existing native core.
public enum KelpieBrowserBuild {
    public static var webKitOnly: Bool { ProcessInfo.processInfo.environment["KELPIE_WEBKIT_ONLY"] == "1" }

    private static let nativeModules = [
        "state", "connect", "protocol", "automation", "mcp", "ai"
    ]

    public static func mac(core: String, additional: SettingsDictionary = [:]) -> SettingsDictionary {
        let native = core + "/native"
        let apple = core + "/apple/macos"
        let flags = nativeModules.map { "-lkelpie_core_" + $0 } + [
            "-lllama", "-lggml", "-lggml-base", "-lggml-cpu", "-lggml-metal", "-lggml-blas",
            "-lc++", "-framework AppIntents", "-framework Metal", "-framework Accelerate"
        ] + (webKitOnly ? [] : ["-framework \"Chromium Embedded Framework\""])
        var settings: SettingsDictionary = [
            "SWIFT_VERSION": "5.0",
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
