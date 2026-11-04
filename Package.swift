// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gatebar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Gatebar", targets: ["Gatebar"]),
    ],
    targets: [
        .target(name: "GatebarCore"),
        .target(name: "GatebarProviders", dependencies: ["GatebarCore"]),
        .executableTarget(name: "Gatebar", dependencies: ["GatebarCore", "GatebarProviders"]),
        .testTarget(name: "GatebarCoreTests", dependencies: ["GatebarCore"]),
    ]
)
