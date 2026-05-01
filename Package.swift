// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snappr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Snappr",
            path: "Sources/Snappr"
        )
    ]
)
