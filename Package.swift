// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsyncImagePipeline",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AsyncImagePipeline",
            targets: ["AsyncImagePipeline"]
        ),
        .library(
            name: "AsyncImagePipelineUI",
            targets: ["AsyncImagePipelineUI"]
        ),
    ],
    targets: [
        .target(
            name: "AsyncImagePipeline",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "AsyncImagePipelineUI",
            dependencies: ["AsyncImagePipeline"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AsyncImagePipelineTests",
            dependencies: ["AsyncImagePipeline"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AsyncImagePipelineUITests",
            dependencies: ["AsyncImagePipelineUI"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
