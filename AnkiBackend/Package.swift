// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SaidAnkiBackend",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "SaidAnkiBackend", targets: ["SaidAnkiBackend"]),
        .library(name: "AnkiProto", targets: ["AnkiProto"]),
    ],
    dependencies: [
        .package(path: "Vendor/SwiftProtobuf"),
    ],
    targets: [
        .binaryTarget(
            name: "AnkiRustLib",
            path: "AnkiRust.xcframework"
        ),
        .target(
            name: "AnkiProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
            ]
        ),
        .target(
            name: "SaidAnkiBackend",
            dependencies: [
                "AnkiRustLib",
                "AnkiProto",
                .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
