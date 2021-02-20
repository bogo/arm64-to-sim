// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "arm64-to-sim",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "arm64-to-sim", targets: ["arm64-to-sim"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "arm64-to-sim",
            dependencies: []),
    ]
)
