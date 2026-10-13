// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lineup",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Lineup", targets: ["Lineup"]),
    ],
    targets: [
        .target(name: "LineupCore"),
        .executableTarget(name: "Lineup", dependencies: ["LineupCore"]),
        .testTarget(name: "LineupCoreTests", dependencies: ["LineupCore"]),
    ],
    swiftLanguageModes: [.v5]
)
