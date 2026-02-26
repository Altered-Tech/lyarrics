// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "lyarrics",
    platforms: [
        // minimum version for OpenAPIHummingbird is v14, Configuration is v15
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.86.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", branch: "revert-linux-trait"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LRCLib",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .executableTarget(
            name: "lyarrics",
            dependencies: [
                .target(name: "LRCLib"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
    ]
)
