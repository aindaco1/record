// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Record",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RecordCore", targets: ["RecordCore"]),
        .library(name: "RecordCapture", targets: ["RecordCapture"]),
        .library(name: "RecordMedia", targets: ["RecordMedia"]),
        .library(name: "RecordSpeech", targets: ["RecordSpeech"]),
        .executable(name: "record", targets: ["Record"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5"),
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
        .target(
            name: "RecordSpeech",
            dependencies: [
                "RecordCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "Record",
            dependencies: [
                "RecordCapture",
                "RecordCore",
                "RecordMedia",
                "RecordSpeech",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // The app assembler installs these directly into Record.app.
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                // Keep direct CLI diagnostics attributable to Record even
                // when the executable is invoked outside the app bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Record/Info.plist",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "RecordCoreTests",
            dependencies: ["RecordCore"]
        ),
        .testTarget(
            name: "RecordTests",
            dependencies: [
                "Record",
                "RecordSpeech",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "RecordCaptureTests",
            dependencies: ["RecordCapture", "RecordCore"]
        ),
        .testTarget(
            name: "RecordMediaTests",
            dependencies: ["RecordCapture", "RecordCore", "RecordMedia"]
        ),
        .testTarget(
            name: "RecordSpeechTests",
            dependencies: [
                "RecordCore",
                "RecordSpeech",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
