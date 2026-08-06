// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Record",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RecordCore", targets: ["RecordCore"]),
        .library(name: "RecordCapture", targets: ["RecordCapture"]),
        .library(name: "RecordMedia", targets: ["RecordMedia"]),
        .executable(name: "record", targets: ["Record"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
    ],
    targets: [
        .target(name: "RecordCore"),
        .target(
            name: "RecordCapture",
            dependencies: ["RecordCore"]
        ),
        .target(
            name: "RecordMedia",
            dependencies: ["RecordCapture", "RecordCore"]
        ),
        .executableTarget(
            name: "Record",
            dependencies: [
                "RecordCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the binary so TCC can attribute the
                // system-audio-capture permission to Record itself when it
                // runs as a LaunchAgent (no .app bundle to carry a plist).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Record/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "RecordCoreTests",
            dependencies: ["RecordCore"]
        ),
        .testTarget(
            name: "RecordCaptureTests",
            dependencies: ["RecordCapture", "RecordCore"]
        ),
        .testTarget(
            name: "RecordMediaTests",
            dependencies: ["RecordCapture", "RecordCore", "RecordMedia"]
        ),
    ]
)
