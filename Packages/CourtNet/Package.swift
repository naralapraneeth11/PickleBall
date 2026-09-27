// swift-tools-version: 6.0
//
//  CourtNet — accounts, friends, squads, chat, confirmed matches and the
//  Feed, backed by Supabase. iPhone only: the Watch talks to the phone.
//
//  CourtNetCore is Foundation-only (wire types, offline outbox, invite
//  links) so it builds and tests on Linux. CourtNet adds the Supabase SDK.
//

import PackageDescription

let package = Package(
    name: "CourtNet",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CourtNet", targets: ["CourtNet"]),
        .library(name: "CourtNetCore", targets: ["CourtNetCore"])
    ],
    dependencies: [
        .package(path: "../CourtKit"),
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.2")
    ],
    targets: [
        .target(name: "CourtNetCore", dependencies: ["CourtKit"]),
        .target(
            name: "CourtNet",
            dependencies: [
                "CourtNetCore",
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(name: "CourtNetCoreTests", dependencies: ["CourtNetCore"])
    ]
)
