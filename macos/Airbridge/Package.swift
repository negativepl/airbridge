// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Airbridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AirbridgeApp", targets: ["AirbridgeApp"]),
        .library(name: "Protocol", targets: ["Protocol"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Clipboard", targets: ["Clipboard"]),
        .library(name: "FileTransfer", targets: ["FileTransfer"]),
        .library(name: "Pairing", targets: ["Pairing"]),
        // Named "AirbridgeSecurity" to avoid collision with Apple's Security.framework
        .library(name: "AirbridgeSecurity", targets: ["AirbridgeSecurity"]),
    ],
    targets: [
        // MARK: - Executable

        .executableTarget(
            name: "AirbridgeApp",
            dependencies: [
                "Protocol",
                "Networking",
                "Clipboard",
                "FileTransfer",
                "Pairing",
                "AirbridgeSecurity",
            ],
            path: "Sources/AirbridgeApp",
            resources: [
                .copy("Resources/airdrop.mp3"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/logo_negative.png"),
                .copy("Resources/logo_claude.png"),
                .copy("Resources/logo_airbridge.png")
            ]
        ),

        // MARK: - Library Targets

        .target(
            name: "Protocol",
            path: "Sources/Protocol"
        ),

        .target(
            name: "Networking",
            dependencies: ["Protocol"],
            path: "Sources/Networking"
        ),

        .target(
            name: "Clipboard",
            dependencies: ["Protocol"],
            path: "Sources/Clipboard"
        ),

        .target(
            name: "FileTransfer",
            dependencies: ["Protocol", "Networking"],
            path: "Sources/FileTransfer"
        ),

        .target(
            name: "Pairing",
            dependencies: ["Protocol", "Networking", "AirbridgeSecurity"],
            path: "Sources/Pairing"
        ),

        .target(
            name: "AirbridgeSecurity",
            path: "Sources/AirbridgeSecurity"
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "ProtocolTests",
            dependencies: ["Protocol"],
            path: "Tests/ProtocolTests"
        ),

        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking"],
            path: "Tests/NetworkingTests"
        ),

        .testTarget(
            name: "ClipboardTests",
            dependencies: ["Clipboard"],
            path: "Tests/ClipboardTests"
        ),

        .testTarget(
            name: "FileTransferTests",
            dependencies: ["FileTransfer"],
            path: "Tests/FileTransferTests"
        ),

        .testTarget(
            name: "PairingTests",
            dependencies: ["Pairing"],
            path: "Tests/PairingTests"
        ),

        .testTarget(
            name: "AirbridgeSecurityTests",
            dependencies: ["AirbridgeSecurity"],
            path: "Tests/AirbridgeSecurityTests"
        ),

        .testTarget(
            name: "IntegrationTests",
            dependencies: ["Networking", "Protocol", "Clipboard", "AirbridgeSecurity"],
            path: "Tests/IntegrationTests"
        ),

        .testTarget(
            name: "AirbridgeAppTests",
            dependencies: ["AirbridgeApp"],
            path: "Tests/AirbridgeAppTests"
        ),
    ]
)
