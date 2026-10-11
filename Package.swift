// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ClaudeCompanion", platforms: [.macOS(.v14)],
  products: [.library(name: "CompanionCore", targets: ["CompanionCore"])],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
  targets: [
    .target(name: "CompanionCore"),
    .executableTarget(name: "CompanionHook", dependencies: ["CompanionCore"]),
    .executableTarget(
      name: "CompanionApp",
      dependencies: ["CompanionCore", .product(name: "Sparkle", package: "Sparkle")],
      resources: [.copy("Resources")],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]),
    .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
  ], swiftLanguageModes: [.v5])
