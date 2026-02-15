// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Recod",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "Recod",
            targets: ["Recod"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Recod",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources",
            exclude: [],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags(["-enable-actor-data-race-checks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        )
    ]
)
