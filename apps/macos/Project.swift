import ProjectDescription
import ProjectDescriptionHelpers

// MARK: - Script phases

let fixCEFStructure = TargetScript.pre(
    script: """
    CEF_FW="${PROJECT_DIR}/../../core/apple/macos/Frameworks/Chromium Embedded Framework.framework"
    if [ -d "$CEF_FW/Resources" ] && [ ! -e "$CEF_FW/Info.plist" ]; then
      ln -sf Resources/Info.plist "$CEF_FW/Info.plist"
    fi
    """,
    name: "Fix CEF Framework Structure"
)

let embedCEFFramework = TargetScript.post(
    script: """
    CEF_SRC="${PROJECT_DIR}/../../core/apple/macos/Frameworks/Chromium Embedded Framework.framework"
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
    # Reconstructing the versioned framework changes its resource layout. Seal
    # that final bundle before Xcode signs the containing app.
    if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
      codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$CEF_DST"
    fi
    """,
    name: "Embed CEF Framework"
)

let embedKelpieHelper = TargetScript.post(
    script: """
    set -euo pipefail
    HELPER_EXE="${BUILT_PRODUCTS_DIR}/KelpieHelper"
    HELPER_ROOT="${BUILT_PRODUCTS_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
    test -x "$HELPER_EXE"

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
        "$exe_path"

      if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --entitlements "${PROJECT_DIR}/../../core/apple/Helpers/KelpieHelper.entitlements" "$app_dir"
      fi
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
    GECKO_SRC="${PROJECT_DIR}/../../core/apple/macos/Frameworks/KelpieGeckoHelper.app"
    GECKO_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/KelpieGeckoHelper.app"
    if [ -d "$GECKO_SRC" ]; then
      rm -rf "$GECKO_DST"
      cp -R "$GECKO_SRC" "$GECKO_DST"
      if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$GECKO_DST"
      fi
      echo "Gecko helper embedded at $GECKO_DST"
    else
      echo "warning: KelpieGeckoHelper.app not found — run 'make gecko-runtime' first"
    fi
    """,
    name: "Embed Gecko Helper"
)

// MARK: - Targets


let kelpieApp = Target.target(
    name: "Kelpie",
    destinations: .macOS,
    product: .app,
    bundleId: "com.kelpie.browser.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .file(path: "Kelpie/Info.plist"),
    sources: [.glob("Kelpie/**/*.swift"), .glob("../updates/apple/**/*.swift")],
    resources: [
        .glob(pattern: "Kelpie/Assets.xcassets"),
        .glob(pattern: "../updates/install-macos.sh"),
    ],
    entitlements: .file(path: KelpieBrowserBuild.webKitOnly ? "Kelpie/Store.entitlements" : "Kelpie/Kelpie.entitlements"),
    scripts: [KelpieBrowserBuild.embedMacResources] + (KelpieBrowserBuild.webKitOnly ? [] : [
        fixCEFStructure,
        embedCEFFramework,
        embedKelpieHelper,
        embedGeckoHelper,
    ]),
    dependencies: [
        .project(target: "KelpieBrowserMac", path: "../../core/apple"),
        .package(product: "AppReveal"),
    ] + (KelpieBrowserBuild.webKitOnly ? [] : [
        .target(name: "KelpieHelper")
    ]),
    settings: .settings(
        base: KelpieBrowserBuild.mac(core: "$(PROJECT_DIR)/../../core", additional: [
            "COMBINE_HIDPI_IMAGES": "YES",
            "ENABLE_APP_SANDBOX": .string(KelpieBrowserBuild.webKitOnly ? "YES" : "NO")
        ])
    )
)



let kelpieEmbeddingHost = Target.target(
    name: "KelpieEmbeddingHost",
    destinations: .macOS,
    product: .app,
    bundleId: "com.unlikeotherai.kelpie.embeddingverify.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .extendingDefault(with: [
        "NSLocalNetworkUsageDescription": "Inspect the local embedding verification host.",
        "NSBonjourServices": ["_appreveal._tcp"]
    ]),
    sources: [.glob("../apple-embedding-host/macos/**/*.swift")],
    scripts: [KelpieBrowserBuild.embedMacResources] +
        (KelpieBrowserBuild.webKitOnly ? [] : [fixCEFStructure, embedCEFFramework, embedKelpieHelper]),
    dependencies: [
        .project(target: "KelpieBrowserMac", path: "../../core/apple"),
        .package(product: "AppReveal")
    ] + (KelpieBrowserBuild.webKitOnly ? [] : [.target(name: "KelpieHelper")]),
    settings: .settings(base: KelpieBrowserBuild.mac(core: "$(PROJECT_DIR)/../../core"))
)


let kelpieEmbeddingUITests = Target.target(
    name: "KelpieEmbeddingUITests",
    destinations: .macOS,
    product: .uiTests,
    bundleId: "com.unlikeotherai.kelpie.embeddingverify.macos.uitests",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [.glob("../apple-embedding-host/UITests/**/*.swift")],
    dependencies: [.target(name: "KelpieEmbeddingHost")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieLibraryTestHost = Target.target(
    name: "KelpieLibraryTestHost",
    destinations: .macOS,
    product: .app,
    bundleId: "com.unlikeotherai.kelpie.tests.macos.host",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [.glob("../apple-test-host/**/*.swift")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieUpdateTests = Target.target(
    name: "KelpieUpdateTests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "com.unlikeotherai.kelpie.updates.tests.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [.glob("../updates/apple/**/*.swift"), .glob("../updates/tests/ReleaseFeedTests.swift")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieTests = Target.target(
    name: "KelpieTests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "com.kelpie.browser.macos.tests",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [
        .glob("Tests/**/*.swift"),
        .glob("Tests/**/*.mm", excluding: KelpieBrowserBuild.webKitOnly ? ["Tests/BrowserControlCDPLifetimeTests.mm"] : []),
    ],
    dependencies: [
        .target(name: "KelpieLibraryTestHost"),
        .project(target: "KelpieBrowserMac", path: "../../core/apple"),
    ],
    settings: .settings(
        base: KelpieBrowserBuild.mac(core: "$(PROJECT_DIR)/../../core")
    )
)

// MARK: - Schemes

let kelpieScheme = Scheme.scheme(
    name: "Kelpie",
    shared: true,
    buildAction: .buildAction(targets: ["Kelpie"]),
    testAction: .targets(
        ["KelpieTests"],
        arguments: KelpieBrowserBuild.webKitOnly ? nil : .arguments(environmentVariables: [
            "DYLD_FRAMEWORK_PATH": "$(BUILT_PRODUCTS_DIR)/Kelpie.app/Contents/Frameworks"
        ]),
        expandVariableFromTarget: "KelpieTests"
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
        kelpieLibraryTestHost,
        kelpieEmbeddingHost,
        kelpieEmbeddingUITests,
        kelpieTests,
        kelpieUpdateTests,
    ] + (KelpieBrowserBuild.webKitOnly ? [] : [KelpieBrowserBuild.cefHelper(core: "../../core")]),
    schemes: [
        .scheme(name: "KelpieUpdateTests", shared: true,
                buildAction: .buildAction(targets: ["KelpieUpdateTests"]),
                testAction: .targets(["KelpieUpdateTests"])),
        kelpieScheme,
        .scheme(name: "KelpieEmbeddingHost", shared: true,
                buildAction: .buildAction(targets: ["KelpieEmbeddingHost"]),
                testAction: .targets(["KelpieEmbeddingUITests"])),
    ]
)
