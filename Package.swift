// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkView",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-cmark", from: "0.4.0"),
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
            dependencies: ["MarkViewCore"],
            path: "Sources/MarkView",
            resources: [
                .copy("Resources"),
            ]
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
    ]
)
