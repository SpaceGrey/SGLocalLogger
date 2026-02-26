// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SGLocalLogger",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SGLocalLogger",
            targets: ["SGLocalLogger"]
        ),
    ],
    targets: [
        .target(
            name: "SGLocalLogger"
        ),
        .testTarget(
            name: "SGLocalLoggerTests",
            dependencies: ["SGLocalLogger"]
        ),
    ]
)
