// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cl10",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "cl10", targets: ["CL10"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CL10",
            path: "Sources/CL10",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
