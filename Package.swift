// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Chroma",
    platforms: [.macOS(.v14)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not make it static: the app already carries DroppyKit, and a
        // second copy inside the droplet gives the same type two metadata
        // records, which fails every cast between them.
        .library(name: "Chroma", type: .dynamic, targets: ["Chroma"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.20.1")
    ],
    targets: [
        .target(
            name: "Chroma",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .testTarget(name: "ChromaTests", dependencies: ["Chroma", .product(name: "DroppyKitHarness", package: "droppykit")]),
        .executableTarget(
            name: "ChromaHarness",
            dependencies: [
                "Chroma",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
