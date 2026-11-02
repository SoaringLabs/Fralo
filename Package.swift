// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fralo",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FraloCore", targets: ["FraloCore"]),
        .library(name: "FraloDesignSystem", targets: ["FraloDesignSystem"]),
        .executable(name: "FraloApp", targets: ["FraloApp"]),
        .executable(name: "fralo", targets: ["FraloCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "FraloLocalization", resources: [.process("Resources")]),
        .target(name: "FraloCore", dependencies: ["FraloLocalization"], resources: [.copy("Resources")]),
        .target(name: "FraloDesignSystem", dependencies: ["FraloLocalization"]),
        .executableTarget(name: "FraloApp", dependencies: ["FraloCore", "FraloDesignSystem", "FraloLocalization", .product(name: "Sparkle", package: "Sparkle")],
                          exclude: ["Development/Fixtures"],
                          resources: [.copy("Resources")],
                          swiftSettings: [.define("FRALO_DEV", .when(configuration: .debug))],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "FraloCLI", dependencies: ["FraloCore"]),
        .testTarget(name: "FraloLocalizationTests", dependencies: ["FraloLocalization"]),
        .testTarget(name: "FraloCoreTests", dependencies: ["FraloCore"]),
        .testTarget(name: "FraloAppTests", dependencies: ["FraloApp"]),
        .testTarget(name: "FraloDesignSystemTests", dependencies: ["FraloDesignSystem"])
    ]
)
