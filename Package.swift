// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "chargewatch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "chargewatch", targets: ["ChargeWatch"])
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
        )
    ]
)
