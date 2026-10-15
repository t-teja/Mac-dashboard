// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacSpaceSaver", targets: ["Headroom"])
    ],
    targets: [
        .target(
            name: "HeadroomCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Headroom",
            dependencies: ["HeadroomCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "HeadroomTests",
            dependencies: ["HeadroomCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
