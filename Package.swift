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
        .package(name: "WalletKitCore", url: "https://github.com/rockwalletcode/WalletKitCore.git", .revision("a142bcfe18d61c01e0bef96ce3f1105b48883247"))
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
