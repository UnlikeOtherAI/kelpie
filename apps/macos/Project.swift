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

let embedChromium = TargetScript.post(
    script: """
    bash "${PROJECT_DIR}/../../scripts/stage-macos-cef.sh" \\
      "${PROJECT_DIR}/../../core/apple/macos/Frameworks/Chromium Embedded Framework.framework" \\
      "${BUILT_PRODUCTS_DIR}/KelpieHelper" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}" \\
      "com.kelpie.browser.helper" "${CURRENT_PROJECT_VERSION:-1}"
    """,
    name: "Embed Chromium framework and helpers"
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
    bundleId: KelpieBrowserBuild.webKitOnly ? "com.unlikeotherai.kelpie" : "com.kelpie.browser.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .file(path: "Kelpie/Info.plist"),
    sources: KelpieBrowserBuild.webKitOnly
        ? [.glob("Kelpie/**/*.swift")]
        : [.glob("Kelpie/**/*.swift"), .glob("../updates/apple/**/*.swift")],
    resources: KelpieBrowserBuild.webKitOnly
        ? [.glob(pattern: "Kelpie/Assets.xcassets")]
        : [.glob(pattern: "Kelpie/Assets.xcassets"), .glob(pattern: "../updates/install-macos.sh")],
    entitlements: .file(path: KelpieBrowserBuild.webKitOnly ? "Kelpie/Store.entitlements" : "Kelpie/Kelpie.entitlements"),
    scripts: [KelpieBrowserBuild.embedMacResources] + (KelpieBrowserBuild.webKitOnly ? [] : [
        fixCEFStructure,
        embedChromium,
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
        "NSBonjourServices": ["_appreveal._tcp", "_kelpie._tcp"]
    ]),
    sources: [.glob("../apple-embedding-host/macos/**/*.swift")],
    scripts: [KelpieBrowserBuild.embedMacResources] +
        (KelpieBrowserBuild.webKitOnly ? [] : [fixCEFStructure, embedChromium]),
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

let kelpieUpdateVerification = Target.target(
    name: "KelpieUpdateVerificationMac",
    destinations: .macOS,
    product: .app,
    bundleId: "com.unlikeotherai.kelpie.update-verification.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .extendingDefault(with: ["CFBundleDisplayName": "Kelpie Update Verification"]),
    sources: [.glob("../updates/apple/**/*.swift"), .glob("../updates/verification-host/**/*.swift")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieUpdateVerificationTests = Target.target(
    name: "KelpieUpdateVerificationUITestsMac",
    destinations: .macOS,
    product: .uiTests,
    bundleId: "com.unlikeotherai.kelpie.update-verification.uitests.macos",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .default,
    sources: [.glob("../updates/verification-tests/**/*.swift")],
    dependencies: [.target(name: "KelpieUpdateVerificationMac")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0"])
)

let kelpieUpdateTests = Target.target(
    name: "KelpieUpdateTestsMac",
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
        .glob("Kelpie/StandaloneInstance.swift"),
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
        kelpieUpdateVerification,
        kelpieUpdateVerificationTests,
    ] + (KelpieBrowserBuild.webKitOnly ? [] : [KelpieBrowserBuild.cefHelper(core: "../../core")]),
    schemes: [
        .scheme(name: "KelpieUpdateVerificationMac", shared: true,
                buildAction: .buildAction(targets: ["KelpieUpdateVerificationMac"]),
                testAction: .targets(["KelpieUpdateVerificationUITestsMac"])),
        .scheme(name: "KelpieUpdatesMac", shared: true,
                buildAction: .buildAction(targets: ["Kelpie"]),
                testAction: .targets(["KelpieUpdateTestsMac"])),
        .scheme(name: "KelpieUpdateTestsMac", shared: true,
                buildAction: .buildAction(targets: ["KelpieUpdateTestsMac"]),
                testAction: .targets(["KelpieUpdateTestsMac"])),
        kelpieScheme,
        .scheme(name: "KelpieEmbeddingHost", shared: true,
                buildAction: .buildAction(targets: ["KelpieEmbeddingHost"]),
                testAction: .targets(["KelpieEmbeddingUITests"])),
    ]
)
