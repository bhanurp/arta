// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ClaudeCompanion", platforms: [.macOS(.v14)], products: [.library(name: "CompanionCore", targets: ["CompanionCore"])], targets: [.target(name: "CompanionCore"), .executableTarget(name: "CompanionHook", dependencies: ["CompanionCore"]), .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"])], swiftLanguageModes: [.v5])
