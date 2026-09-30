// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CursorBridge", targets: ["CursorBridge"]),
    ],
    targets: [
        .target(name: "CursorBridgeCore"),
        .executableTarget(
            name: "CursorBridge",
            dependencies: ["CursorBridgeCore"]
        ),
        .testTarget(
            name: "CursorBridgeCoreTests",
            dependencies: ["CursorBridgeCore"]
        ),
    ]
)
