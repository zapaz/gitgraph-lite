// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitGraphLite",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GitGraphLite", targets: ["GitGraphLite"])],
    targets: [
        .target(name: "GitGraphCore"),
        .executableTarget(name: "GitGraphLite", dependencies: ["GitGraphCore"]),
        .executableTarget(name: "GitGraphChecks", dependencies: ["GitGraphCore"], path: "Tests/GitGraphCoreTests")
    ]
)
