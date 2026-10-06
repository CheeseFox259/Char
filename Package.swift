// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Char",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CharCore", targets: ["CharCore"]),
        .library(name: "CharObservations", targets: ["CharObservations"]),
        .library(name: "CharPlatform", targets: ["CharPlatform"]),
        .executable(name: "Char", targets: ["CharApp"]),
        .executable(name: "char-hook", targets: ["CharHook"]),
        .executable(name: "char-package-check", targets: ["CharPackageCheck"]),
        .executable(name: "char-plugin-check", targets: ["CharPluginCheck"]),
        .executable(name: "char-plugin-checks", targets: ["CharPluginChecks"]),
        .executable(name: "char-core-checks", targets: ["CharCoreChecks"]),
        .executable(name: "char-observation-checks", targets: ["CharObservationChecks"]),
        .executable(name: "char-platform-checks", targets: ["CharPlatformChecks"])
    ],
    targets: [
        .target(name: "CharCore"),
        .target(name: "CharObservations", dependencies: ["CharCore"]),
        .target(name: "CharPlatform", dependencies: ["CharCore"]),
        .target(name: "CharPluginHost", dependencies: ["CharCore"]),
        .executableTarget(name: "CharApp", dependencies: ["CharCore", "CharObservations", "CharPlatform", "CharPluginHost"]),
        .executableTarget(name: "CharHook", dependencies: ["CharCore", "CharObservations"]),
        .executableTarget(name: "CharPackageCheck", dependencies: ["CharCore", "CharPlatform"]),
        .executableTarget(name: "CharPluginCheck", dependencies: ["CharCore", "CharPluginHost"]),
        .executableTarget(name: "CharPluginChecks", dependencies: ["CharCore", "CharPluginHost"], path: "Tests/CharPluginChecks"),
        .executableTarget(name: "CharCoreChecks", dependencies: ["CharCore"], path: "Tests/CharCoreChecks"),
        .executableTarget(name: "CharObservationChecks", dependencies: ["CharObservations"], path: "Tests/CharObservationChecks"),
        .executableTarget(name: "CharPlatformChecks", dependencies: ["CharPlatform"], path: "Tests/CharPlatformChecks")
    ],
    swiftLanguageModes: [.v5]
)
