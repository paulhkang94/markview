// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MarkView",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-cmark", from: "0.4.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.4.0"),
    ],
    targets: [
        // Core library with renderer and file watcher (no UI dependencies for testability)
        .target(
            name: "MarkViewCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/MarkViewCore"
        ),
        // Main app executable
        .executableTarget(
            name: "MarkView",
            dependencies: [
                "MarkViewCore",
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Sources/MarkView",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources"),
            ]
        ),
        // MCP server — stdio JSON-RPC server for AI tool integration
        .executableTarget(
            name: "MarkViewMCPServer",
            dependencies: [
                "MarkViewCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MarkViewMCPServer"
        ),
        // Test runner (standalone executable — no XCTest dependency)
        .executableTarget(
            name: "MarkViewTestRunner",
            dependencies: ["MarkViewCore"],
            path: "Tests/TestRunner",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        // Fuzz tester — random markdown inputs, assert no crashes
        .executableTarget(
            name: "MarkViewFuzzTester",
            dependencies: ["MarkViewCore"],
            path: "Tests/FuzzTester"
        ),
        // Differential tester — compare output vs cmark-gfm CLI
        .executableTarget(
            name: "MarkViewDiffTester",
            dependencies: ["MarkViewCore"],
            path: "Tests/DiffTester"
        ),
        // E2E tester — launches real .app, interacts via Accessibility APIs
        .executableTarget(
            name: "MarkViewE2ETester",
            path: "Tests/E2ETester"
        ),
        // Visual regression tester — screenshot comparison via offscreen WKWebView
        .executableTarget(
            name: "MarkViewVisualTester",
            dependencies: ["MarkViewCore"],
            path: "Tests/VisualTester",
            exclude: ["Goldens"]
        ),
        // Quick Look extension — renders .md files in Finder preview
        .executableTarget(
            name: "MarkViewQuickLook",
            dependencies: ["MarkViewCore"],
            path: "Sources/MarkViewQuickLook",
            exclude: ["Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-application-extension"]),
            ]
        ),
    ]
)
