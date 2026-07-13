// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftProtobuf",
    platforms: [.iOS(.v12), .macOS(.v10_13)],
    products: [
        .library(name: "SwiftProtobuf", targets: ["SwiftProtobuf"]),
    ],
    targets: [
        .target(
            name: "SwiftProtobuf",
            path: "Sources/SwiftProtobuf",
            exclude: ["CMakeLists.txt"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
