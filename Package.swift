// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AulaF87ProStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AulaF87ProStudio", targets: ["AulaF87ProStudio"])
    ],
    targets: [
        .executableTarget(
            name: "AulaF87ProStudio",
            path: "Sources/AulaF87ProStudio",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
