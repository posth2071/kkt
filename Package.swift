// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kkt",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KktCore", targets: ["KktCore"]),
        .executable(name: "kkt", targets: ["kkt"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .systemLibrary(name: "CSQLCipher", pkgConfig: "sqlcipher", providers: [.brew(["sqlcipher"])]),
        .target(name: "KktCore", dependencies: ["CSQLCipher"]),
        .executableTarget(name: "kkt", dependencies: ["KktCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "KktCoreTests", dependencies: ["KktCore", "CSQLCipher"]),
    ]
)
