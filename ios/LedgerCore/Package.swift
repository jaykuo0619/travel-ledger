// swift-tools-version:5.9
import PackageDescription

// Everything that does not need a screen: the database, file import/export, formatting.
// Runs with `swift test` on a Mac (and on Linux), without the simulator.
let package = Package(
    name: "LedgerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LedgerCore", targets: ["LedgerCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "LedgerCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), "ZIPFoundation"]
        ),
        .testTarget(
            name: "LedgerCoreTests",
            dependencies: ["LedgerCore"]
        ),
    ]
)
