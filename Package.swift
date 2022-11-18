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
        .package(name: "WalletKitCore", url: "https://github.com/rockwalletcode/WalletKitCore.git", .revision("713b9be4f2fac8953aa2752efaf636e732ef0462"))
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
