// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EctoRemote",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "EctoRemote",
            path: "Sources/EctoRemote"
        )
    ]
)
