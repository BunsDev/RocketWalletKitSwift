// swift-tools-version:5.3
//
import PackageDescription

let package = Package(
    name: "WalletKit",
    platforms: [
        .iOS(.v11),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "WalletKit",
            targets: ["WalletKit"]
        ),
    ],

    dependencies: [
        .package(name: "WalletKitCore", url: "https://github.com/fabriik/WalletKitCore", .branchItem("mit"))
    ],

    targets: [
        .target(
            name: "WalletKit",
            dependencies: [
                .product(name: "WalletKitCore", package: "WalletKitCore"),
            ],
            path: "WalletKit"
        ),
    ]
)
