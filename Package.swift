// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TokenJump", platforms: [.macOS(.v14)], products: [.executable(name: "TokenJump", targets: ["TokenJump"])], targets: [.executableTarget(name: "TokenJump")], swiftLanguageVersions: [.v5])
