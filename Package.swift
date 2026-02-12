// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacAudio2",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacAudio2",
            targets: ["MacAudio2"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacAudio2",
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
