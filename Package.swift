// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickDict",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuickDict",
            path: "Sources"
        )
    ]
)
