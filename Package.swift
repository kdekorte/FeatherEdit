// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FeatherEdit",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FeatherEdit",
            path: "Sources/FeatherEdit",
            resources: [
                .copy("Resources/FeatherEdit.icns")
            ]
        )
    ]
)
