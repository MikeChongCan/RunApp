import ProjectDescription

// RunApp.app. The generated RunApp.xcodeproj is not in git: run Scripts/generate.
// Sources are buildable (synchronized) folders: add files on disk, never here.
// Settings are written out in full (defaultSettings: .none) so nothing changes with a Tuist update.

let marketingVersion = "0.1.0"
let buildNumber = "1"

let projectSettings: Settings = .settings(
    base: [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEAD_CODE_STRIPPING": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "15.0",
        "SDKROOT": "macosx",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
        // "Sign to Run Locally": ad-hoc signature, no team needed. Scripts/release overrides these
        // on the command line with Developer ID Application: RockieStar Inc. (DH5UQL44AR).
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Manual",
        "DEVELOPMENT_TEAM": "",
        "ENABLE_HARDENED_RUNTIME": "YES",
    ],
    debug: [
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    ],
    release: [
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
    ],
    defaultSettings: .none
)

/// Lets `open -a RunApp <path>` hand folders and projects to a running instance
/// (AppDelegate.application(_:open:)). Rank None: RunApp is never the default opener.
let documentTypes: Plist.Value = .array([
    .dictionary([
        "CFBundleTypeName": "Folder",
        "CFBundleTypeRole": "Viewer",
        "LSHandlerRank": "None",
        "LSItemContentTypes": ["public.folder"],
    ]),
    .dictionary([
        "CFBundleTypeName": "Xcode Project",
        "CFBundleTypeRole": "Viewer",
        "LSHandlerRank": "None",
        "LSItemContentTypes": ["com.apple.xcode.project", "com.apple.dt.document.workspace"],
    ]),
    .dictionary([
        "CFBundleTypeName": "Swift Package",
        "CFBundleTypeRole": "Viewer",
        "LSHandlerRank": "None",
        "LSItemContentTypes": ["public.swift-source"],
    ]),
])

let appInfoPlist: InfoPlist = .extendingDefault(with: [
    "CFBundleDisplayName": "RunApp",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "CFBundleDocumentTypes": documentTypes,
    "LSApplicationCategoryType": "public.app-category.developer-tools",
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "NSHumanReadableCopyright": "Copyright © 2026 RunApp contributors. MIT License.",
    "NSPrincipalClass": "NSApplication",
    // Sparkle 2 auto-updates (Scripts/release publishes appcast.xml).
    "SUFeedURL": "https://raw.githubusercontent.com/MikeChongCan/RunApp/main/appcast.xml",
    "SUPublicEDKey": "rxGt1cAJBTcmpx28Dl8kK48a0B3pqCKcPgAfoiOP/Gw=",
    "SUEnableAutomaticChecks": true,
])

let project = Project(
    name: "RunApp",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "en",
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    settings: projectSettings,
    targets: [
        .target(
            name: "RunApp",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.runapp.RunApp",
            deploymentTargets: .macOS("15.0"),
            infoPlist: appInfoPlist,
            buildableFolders: ["RunApp"],
            dependencies: [.package(product: "Sparkle")],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "COMBINE_HIDPI_IMAGES": "YES",
                    "CURRENT_PROJECT_VERSION": .string(buildNumber),
                    // Not sandboxed on purpose: RunApp spawns sweetpad and xcodebuild. No entitlements file.
                    "ENABLE_APP_SANDBOX": "NO",
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
                    "MARKETING_VERSION": .string(marketingVersion),
                    "PRODUCT_BUNDLE_IDENTIFIER": "dev.runapp.RunApp",
                    "PRODUCT_NAME": "RunApp",
                ],
                defaultSettings: .none
            )
        ),
        .target(
            name: "RunAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.runapp.RunAppTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            buildableFolders: ["RunAppTests"],
            dependencies: [.target(name: "RunApp")],
            settings: .settings(
                base: [
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "PRODUCT_BUNDLE_IDENTIFIER": "dev.runapp.RunAppTests",
                    "PRODUCT_NAME": "RunAppTests",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/RunApp.app/Contents/MacOS/RunApp",
                ],
                defaultSettings: .none
            )
        ),
    ],
    schemes: [
        .scheme(
            name: "RunApp",
            shared: true,
            buildAction: .buildAction(targets: ["RunApp"]),
            testAction: .targets(
                [.testableTarget(target: "RunAppTests", parallelization: .swiftTestingOnly)],
                configuration: "Debug"
            ),
            runAction: .runAction(configuration: "Debug", executable: "RunApp"),
            archiveAction: .archiveAction(configuration: "Release"),
            profileAction: .profileAction(configuration: "Release", executable: "RunApp"),
            analyzeAction: .analyzeAction(configuration: "Debug")
        ),
    ],
    resourceSynthesizers: []
)
