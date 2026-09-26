// swift-tools-version: 6.0
//
//  CourtKit — the rules and data layer shared by the iPhone and Apple Watch apps.
//
//  Everything in here is pure Swift (Foundation only) so it builds and tests on
//  any platform, including Linux CI. UI, persistence and connectivity live in
//  the app targets and talk to this package through value types.
//

import PackageDescription

let package = Package(
    name: "CourtKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CourtKit", targets: ["CourtKit"])
    ],
    targets: [
        .target(name: "CourtKit"),
        .testTarget(name: "CourtKitTests", dependencies: ["CourtKit"])
    ]
)
