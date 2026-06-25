// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDXF",
    products: [
        .library(name: "SwiftDXF", targets: ["SwiftDXF"]),
        .executable(name: "dxfdump", targets: ["dxfdump"]),
    ],
    targets: [
        .target(name: "SwiftDXF"),
        .executableTarget(name: "dxfdump", dependencies: ["SwiftDXF"]),
        .testTarget(name: "SwiftDXFTests", dependencies: ["SwiftDXF"]),
    ]
)
