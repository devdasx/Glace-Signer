// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlaceSignerCoreVerification",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(
            url: "https://github.com/anquii/ripemd160.git",
            exact: "1.0.0"
        ),
        .package(
            url: "https://github.com/21-DOT-DEV/swift-secp256k1.git",
            exact: "0.23.2"
        )
    ],
    targets: [
        .target(
            name: "GlaceSignerCore",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "RIPEMD160", package: "RIPEMD160")
            ],
            path: "GlaceSigner",
            exclude: [
                "Features",
                "GlaceSignerApp.swift",
                "Resources/Assets.xcassets",
                "Resources/InfoPlist.xcstrings",
                "Resources/Localizable.xcstrings",
                "Security/OfflineNetworkMonitor.swift"
            ],
            sources: [
                "Bitcoin",
                "Security/NetworkIsolationPolicy.swift",
                "Security/SignerWalletVault.swift"
            ],
            resources: [
                .copy("Resources/BIP39")
            ]
        ),
        .testTarget(
            name: "GlaceSignerCoreTests",
            dependencies: ["GlaceSignerCore"],
            path: "GlaceSignerTests"
        )
    ]
)
