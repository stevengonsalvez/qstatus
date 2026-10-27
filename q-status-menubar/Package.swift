// swift-tools-version: 6.0
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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["Core"],
            path: "Sources/App",
            swiftSettings: [
                .define("SWIFTUI_APP"),
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/Core",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/CoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)