// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RivetdeckNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RivetdeckCore", targets: ["RivetdeckCore"]),
        .executable(name: "RivetdeckNative", targets: ["RivetdeckNative"]),
        .executable(name: "dsh-probe", targets: ["DSHProbe"])
    ],
    targets: [
        .target(name: "RivetdeckCore"),
        .executableTarget(name: "RivetdeckNative", dependencies: ["RivetdeckCore"]),
        .executableTarget(name: "DSHProbe", dependencies: ["RivetdeckCore"]),
        .testTarget(name: "RivetdeckCoreTests", dependencies: ["RivetdeckCore"], resources: [.copy("Fixtures")])
    ]
)
