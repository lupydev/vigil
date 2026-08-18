// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VigilCore", targets: ["VigilCore"]),
        .executable(name: "vigil", targets: ["VigilApp"]),
        .executable(name: "coretests", targets: ["CoreTests"]),
    ],
    targets: [
        // Pure domain. No system imports, no I/O, fully testable.
        .target(name: "VigilCore"),

        // Adapters that bind the domain ports to macOS.
        .target(name: "VigilSystem", dependencies: ["VigilCore"]),

        // Menu bar shell.
        .executableTarget(
            name: "VigilApp",
            dependencies: ["VigilCore", "VigilSystem"]
        ),

        // Domain tests. This is an executable rather than a `.testTarget`
        // because XCTest and swift-testing both require full Xcode, and this
        // machine has only the Command Line Tools. Run it with
        // `swift run coretests`; it exits non-zero on failure.
        .executableTarget(name: "CoreTests", dependencies: ["VigilCore"]),
    ]
)
