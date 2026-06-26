// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pesty",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pesty", targets: ["Pesty"])
    ],
    targets: [
        .executableTarget(
            name: "Pesty",
            path: "Sources/Pesty",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
