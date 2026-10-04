// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Clipr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Clipr",
            path: "Sources/Clipr",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "ClipprTests",
            dependencies: ["Clipr"],
            path: "Tests/ClipprTests"
        )
    ]
)
