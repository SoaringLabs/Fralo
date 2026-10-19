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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "FraloCore"),
        .executableTarget(name: "FraloApp", dependencies: ["FraloCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "FraloCLI", dependencies: ["FraloCore"]),
        .testTarget(name: "FraloCoreTests", dependencies: ["FraloCore"]),
        .testTarget(name: "FraloAppTests", dependencies: ["FraloApp"])
    ]
)
