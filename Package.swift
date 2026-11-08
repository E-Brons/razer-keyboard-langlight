// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "langlight",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RazerBLE", targets: ["RazerBLE"]),
        .executable(name: "langlight", targets: ["langlight"]),
    ],
    targets: [
        .target(name: "RazerBLE"),
        .executableTarget(
            name: "langlight",
            dependencies: ["RazerBLE"],
            linkerSettings: [
                // Embed Info.plist so macOS shows the Bluetooth permission prompt for a bare binary.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"]),
            ]),
        .testTarget(name: "RazerBLETests", dependencies: ["RazerBLE"]),
        .testTarget(name: "langlightTests", dependencies: ["langlight"]),
    ]
)
