// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fralo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FraloCore", targets: ["FraloCore"]),
        .executable(name: "FraloApp", targets: ["FraloApp"]),
        .executable(name: "fralo", targets: ["FraloCLI"])
    ],
    targets: [
        .target(name: "FraloCore"),
        .executableTarget(name: "FraloApp", dependencies: ["FraloCore"]),
        .executableTarget(name: "FraloCLI", dependencies: ["FraloCore"]),
        .testTarget(name: "FraloCoreTests", dependencies: ["FraloCore"])
    ]
)
