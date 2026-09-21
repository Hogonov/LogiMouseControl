// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LogiMouseControl", platforms: [.macOS(.v14)], products: [
    .executable(name: "LogiMouseControl", targets: ["LogiMouseControl"])
], targets: [
    .target(name: "MouseCore"),
    .executableTarget(name: "LogiMouseControl", dependencies: ["MouseCore"], resources: [.copy("DeviceImages")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit"), .linkedFramework("ApplicationServices"), .linkedFramework("ServiceManagement")]),
    .executableTarget(name: "MouseCoreChecks", dependencies: ["MouseCore"], path: "Tests/MouseCoreTests")
])
