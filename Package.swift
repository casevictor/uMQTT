// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uMQTT",
    products: [
        .library(
            name: "uMQTT",
            targets: ["uMQTT"]),
    ],
    targets: [
        .target(
            name: "uMQTT",
            path: "Sources/uMQTT"),
        .testTarget(
            name: "uMQTTTests",
            dependencies: ["uMQTT"],
            path: "Tests/uMQTTTests"),
    ]
)
