import ProjectDescription

// MARK: - Script phases

let fixCEFStructure = TargetScript.pre(
    script: """
    CEF_FW="${PROJECT_DIR}/Frameworks/Chromium Embedded Framework.framework"
    if [ -d "$CEF_FW/Resources" ] && [ ! -e "$CEF_FW/Info.plist" ]; then
      ln -sf Resources/Info.plist "$CEF_FW/Info.plist"
    fi
    """,
    name: "Fix CEF Framework Structure"
)

let embedCEFFramework = TargetScript.post(
    script: """
    CEF_SRC="${PROJECT_DIR}/Frameworks/Chromium Embedded Framework.framework"
    CEF_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/Chromium Embedded Framework.framework"
    rm -rf "$CEF_DST"
    mkdir -p "$CEF_DST/Versions/A"
    cp "$CEF_SRC/Chromium Embedded Framework" "$CEF_DST/Versions/A/"
    rsync -a "$CEF_SRC/Resources/" "$CEF_DST/Versions/A/Resources/"
    if [ -d "$CEF_SRC/Libraries" ]; then
      rsync -a "$CEF_SRC/Libraries/" "$CEF_DST/Versions/A/Libraries/"
      ln -sf Versions/Current/Libraries "$CEF_DST/Libraries"
    fi
    ln -sf A "$CEF_DST/Versions/Current"
    ln -sf "Versions/Current/Chromium Embedded Framework" "$CEF_DST/Chromium Embedded Framework"
    ln -sf Versions/Current/Resources "$CEF_DST/Resources"
    """,
    name: "Embed CEF Framework"
)

let embedKelpieHelper = TargetScript.post(
    script: """
    HELPER_EXE="${BUILT_PRODUCTS_DIR}/KelpieHelper"
    HELPER_ROOT="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

    stage_helper() {
      local helper_name="$1"
      local bundle_id="$2"
      local app_dir="${HELPER_ROOT}/${helper_name}.app"
      local exe_dir="${app_dir}/Contents/MacOS"
      local exe_path="${exe_dir}/${helper_name}"
      local plist_path="${app_dir}/Contents/Info.plist"

      mkdir -p "$exe_dir"
      cp "$HELPER_EXE" "$exe_path"

      /usr/libexec/PlistBuddy -c "Clear dict" "$plist_path" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${helper_name}" "$plist_path"
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_id}" "$plist_path"
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${helper_name}" "$plist_path"
      /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist_path"
      /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$plist_path"
      /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist_path"

      install_name_tool -change \\
        "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \\
        "@executable_path/../../../Chromium Embedded Framework.framework/Chromium Embedded Framework" \\
        "$exe_path" 2>/dev/null || true

      codesign -fs - "$exe_path" 2>/dev/null || true
      codesign -fs - "$app_dir" 2>/dev/null || true
    }

    rm -rf \\
      "${HELPER_ROOT}/Kelpie Helper.app" \\
      "${HELPER_ROOT}/Kelpie Helper (Renderer).app" \\
      "${HELPER_ROOT}/Kelpie Helper (GPU).app" \\
      "${HELPER_ROOT}/Kelpie Helper (Plugin).app" \\
      "${HELPER_ROOT}/Kelpie Helper (Alerts).app"

    stage_helper "Kelpie Helper" "com.kelpie.browser.helper"
    stage_helper "Kelpie Helper (Renderer)" "com.kelpie.browser.helper.renderer"
    stage_helper "Kelpie Helper (GPU)" "com.kelpie.browser.helper.gpu"
    stage_helper "Kelpie Helper (Plugin)" "com.kelpie.browser.helper.plugin"
    stage_helper "Kelpie Helper (Alerts)" "com.kelpie.browser.helper.alerts"
    """,
    name: "Embed KelpieHelper"
)

let embedGeckoHelper = TargetScript.post(
    script: """
    GECKO_SRC="${PROJECT_DIR}/Frameworks/KelpieGeckoHelper.app"
    GECKO_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/KelpieGeckoHelper.app"
    if [ -d "$GECKO_SRC" ]; then
      rm -rf "$GECKO_DST"
      cp -R "$GECKO_SRC" "$GECKO_DST"
      codesign -fs - "$GECKO_DST" 2>/dev/null || true
      echo "Gecko helper embedded at $GECKO_DST"
    else
      echo "warning: KelpieGeckoHelper.app not found — run 'make gecko-runtime' first"
    fi
    """,
    name: "Embed Gecko Helper"
)

// MARK: - Linker flags

let macOSLinkerFlags: SettingValue = .array([
    "-lkelpie_core_state",
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

// MARK: - Targets

let kelpieApp = Target.target(
    name: "Kelpie",
    destinations: .macOS,
    product: .app,
    bundleId: "com.kelpie.browser.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .file(path: "Kelpie/Info.plist"),
    sources: [
        .glob("Kelpie/**/*.swift"),
        .glob("Kelpie/**/*.mm"),
    ],
    resources: [
        .glob(pattern: "Kelpie/Assets.xcassets"),
        .glob(pattern: "Kelpie/Resources/**"),
    ],
    entitlements: .file(path: "Kelpie/Kelpie.entitlements"),
    scripts: [
        fixCEFStructure,
        embedCEFFramework,
        embedKelpieHelper,
        embedGeckoHelper,
    ],
    dependencies: [
        .target(name: "KelpieHelper"),
        .package(product: "AppReveal"),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
            "SWIFT_OBJC_BRIDGING_HEADER": "Kelpie/Kelpie-Bridging-Header.h",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/Kelpie/Renderer",
                "$(PROJECT_DIR)/../../native/core-state/include",
                "$(PROJECT_DIR)/../../native/core-protocol/include",
                "$(PROJECT_DIR)/../../native/core-automation/include",
                "$(PROJECT_DIR)/../../native/core-mcp/include",
                "$(PROJECT_DIR)/../../native/core-ai/include",
                "$(PROJECT_DIR)/Frameworks/cef_include",
                "$(PROJECT_DIR)/vendor/llama.cpp/include",
            ]),
            "LIBRARY_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/../../native/.build/core-state",
                "$(PROJECT_DIR)/../../native/.build/core-protocol",
                "$(PROJECT_DIR)/../../native/.build/core-automation",
                "$(PROJECT_DIR)/../../native/.build/core-mcp",
                "$(PROJECT_DIR)/../../native/.build/core-ai",
                "$(PROJECT_DIR)/vendor/llama.cpp/lib",
            ]),
            "FRAMEWORK_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/Frameworks",
            ]),
            "OTHER_LDFLAGS": macOSLinkerFlags,
            "COMBINE_HIDPI_IMAGES": "YES",
            "ENABLE_APP_SANDBOX": "NO",
            "GENERATE_APP_INTENTS_METADATA": "NO",
            "APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING": "NO",
        ]
    )
)

let kelpieHelper = Target.target(
    name: "KelpieHelper",
    destinations: .macOS,
    product: .commandLineTool,
    bundleId: "com.kelpie.browser.helper",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .file(path: "KelpieHelper/Info.plist"),
    sources: [
        .glob("KelpieHelper/**/*.mm"),
    ],
    entitlements: .file(path: "KelpieHelper/KelpieHelper.entitlements"),
    settings: .settings(
        base: [
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
            "HEADER_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/Frameworks/cef_include",
            ]),
            "FRAMEWORK_SEARCH_PATHS": .array([
                "$(PROJECT_DIR)/Frameworks",
            ]),
            "OTHER_LDFLAGS": .array([
                "-framework \"Chromium Embedded Framework\"",
                "-lc++",
            ]),
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
        kelpieHelper,
    ]
)
