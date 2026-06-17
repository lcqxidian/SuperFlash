// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperFlash",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SuperFlash",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
