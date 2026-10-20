// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeridianCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeridianCore", targets: ["MeridianCore"]),
        .executable(name: "meridian-sim", targets: ["meridian-sim"]),
    ],
    targets: [
        .target(
            name: "MeridianCore",
            resources: [.copy("Data")]
        ),
        .executableTarget(name: "meridian-sim", dependencies: ["MeridianCore"]),
        .testTarget(name: "MeridianCoreTests", dependencies: ["MeridianCore"]),
    ]
)
