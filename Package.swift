// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "chargewatch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "chargewatch", targets: ["ChargeWatch"]),
        .executable(name: "chargewatch-helper", targets: ["ChargeWatchHelper"])
    ],
    targets: [
        .executableTarget(
            name: "ChargeWatch",
            path: "Sources/ChargeWatch",
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
