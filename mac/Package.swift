// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Termaid",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TermaidCore", targets: ["TermaidCore"]),
        .executable(name: "termaid-mac", targets: ["termaid-mac"]),
        .executable(name: "TermaidApp", targets: ["TermaidApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0"),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12024/llama-b12024-xcframework.zip",
            checksum: "b7005ad25dab07d273794afc7ac24d55aeac1b52376301907c5fb4762e42545d"
        ),
        .target(
            name: "TermaidCore",
            dependencies: ["llama", "FluidAudio"],
            resources: [.copy("Resources/engine.js")]
        ),
        .executableTarget(name: "termaid-mac", dependencies: ["TermaidCore"]),
        // The menu-bar app: the capsule, voice and typed input, the Library.
        .executableTarget(name: "TermaidApp", dependencies: ["TermaidCore"]),
        .testTarget(name: "TermaidCoreTests", dependencies: ["TermaidCore"]),
    ],
    // JavaScriptCore and llama.cpp handles aren't Sendable; each wrapper serialises access itself.
    swiftLanguageModes: [.v5]
)
