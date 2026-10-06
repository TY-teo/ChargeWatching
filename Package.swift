// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "chargewatch",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "chargewatch", targets: ["ChargeWatch"]),
        .executable(name: "chargewatch-helper", targets: ["ChargeWatchHelper"])
    ],
    targets: [
        .executableTarget(
            name: "ChargeWatch",
            path: "Sources/ChargeWatch",
            resources: [
                .process("UI/Resources"),
                // en/ru/zh-Hans .lproj — 经 Bundle.module 解析（见 UI/Localization.swift）
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "ChargeWatchHelper",
            path: "Sources/ChargeWatchHelper",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
