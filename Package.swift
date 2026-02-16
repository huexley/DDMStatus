// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DDMStatusApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DDMStatusApp",
            path: ".",
            sources: ["DDMStatusApp.swift"],
            linkerSettings: [
                .unsafeFlags(["-framework", "Cocoa"]),
                .unsafeFlags(["-framework", "SwiftUI"])
            ]
        )
    ]
)
