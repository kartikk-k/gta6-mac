// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ViceNights",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ViceNights", path: "Sources/ViceNights")
    ]
)
