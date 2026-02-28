// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SherpaOnnx",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SherpaOnnxSwift", targets: ["SherpaOnnxSwift"]),
    ],
    targets: [
        // Pre-built static xcframework (sherpa-onnx + onnxruntime merged)
        .binaryTarget(
            name: "SherpaOnnxBinary",
            path: "sherpa-onnx.xcframework"
        ),
        // C module: exposes c-api.h to Swift via modulemap
        .target(
            name: "CSherpaOnnx",
            dependencies: ["SherpaOnnxBinary"],
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        // Swift wrapper: high-level Swift API
        .target(
            name: "SherpaOnnxSwift",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/SherpaOnnxSwift"
        ),
    ]
)
