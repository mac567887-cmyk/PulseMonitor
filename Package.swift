// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PulseMonitor", targets: ["PulseMonitor"])
    ],
    targets: [
        .target(
            name: "LibprocBridge",
            path: "SourcesC",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "PulseMonitor",
            dependencies: ["LibprocBridge"],
            path: "PulseMonitor",
            exclude: [
                "Resources/Info.plist",
                "Resources/PulseMonitor.entitlements",
                "Resources/PulseMonitor-Bridging-Header.h",
                "Resources/Assets.xcassets"
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("Metal"),
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("proc")
            ]
        )
    ]
)
