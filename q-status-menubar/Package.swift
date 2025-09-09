// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QStatusMenubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QStatusMenubar", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.26.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["Core"],
            path: "Sources/App",
            resources: [
                // We will add assets/Info.plist when we switch to Xcode app target
            ],
            swiftSettings: [
                .define("SWIFTUI_APP")
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/Core"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        )
    ]
)
