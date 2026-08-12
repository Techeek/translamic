// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TranslaMic",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.0"),
    ],
    targets: [
        .executableTarget(
            name: "TranslaMic",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources/TranslaMicApp",
            resources: [
                .copy("Resources/AppIcon/AppIcon-512.png"),
                .copy("Resources/silero_vad.onnx"),
            ]
        ),
        .testTarget(
            name: "TranslaMicTests",
            dependencies: ["TranslaMic"],
            path: "Tests/TranslaMicTests"
        ),
    ]
)
