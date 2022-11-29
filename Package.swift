// swift-tools-version:5.3
//
import PackageDescription

let package = Package(
    name: "WalletKit",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "WalletKit",
            targets: ["WalletKit"]
        ),
    ],

    dependencies: [
        .package(name: "WalletKitCore", url: "https://github.com/rockwalletcode/WalletKitCore.git", .revision("4e26d4fd650503373e389971cbc41af45e06bf89"))
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
