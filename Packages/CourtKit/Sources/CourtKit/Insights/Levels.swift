//
//  Levels.swift
//  CourtKit
//
//  A personal level per sport, worked out on the phone from confirmed
//  results. Under the hood it's an Elo rating (everyone starts at 1000);
//  on screen it's a level on the familiar 1.0–7.0 scale, starting at 3.0.
//
//  • Expected result from the rating gap between the two sides (a pair
//    counts as the average of its players).
//  • Actual result is mostly win or loss, partly the share of points won,
//    so an 11-9 loss to a stronger pair still says something good.
//  • New players move fast (K 48 for their first 10 matches), then settle
//    (K 24). Under 5 matches the level is provisional.
//
//  Each player publishes their own level so friends see the same number
//  even when they can't see every match it came from.
//

import Foundation

public struct PlayerLevel: Hashable, Codable, Sendable {
    public static let startingRating = 1000.0
    public static let provisionalMatches = 5

    public internal(set) var rating: Double = PlayerLevel.startingRating
    public internal(set) var matches = 0
    /// Level change over the last five matches.
    public internal(set) var recentChange = 0.0
    internal var recent: [Double] = []

    public init() {}

    public var level: Double { Self.level(for: rating) }
    public var isProvisional: Bool { matches < Self.provisionalMatches }

    /// "3.42"
    public var formatted: String { Self.format(level) }

    public static func level(for rating: Double) -> Double {
        min(7.0, max(1.0, 3.0 + (rating - startingRating) / 250))
    }

    public static func format(_ level: Double) -> String {
        String(format: "%.2f", level)
    }
}

public struct LevelBook: Hashable, Sendable {
    public private(set) var levels: [Sport: [PlayerID: PlayerLevel]] = [:]

    public init() {}

    /// Folds confirmed matches oldest first.
    public static func compute(_ results: [MatchResult]) -> LevelBook {
        var book = LevelBook()
        for result in results.sorted(by: BeltLedger.chronological) {
            book.record(result)
        }
        return book
    }

    public func level(of player: PlayerID, in sport: Sport) -> PlayerLevel? {
        levels[sport]?[player]
    }

    /// What to publish to the profile: {"pickleball": 3.42}.
    public func published(for player: PlayerID) -> [String: Double] {
        var out: [String: Double] = [:]
        for (sport, table) in levels {
            if let level = table[player], !level.isProvisional {
                out[sport.rawValue] = (level.level * 100).rounded() / 100
            }
        }
        return out
    }

    mutating func record(_ result: MatchResult) {
        guard let winner = result.winner else { return }
        let a = result.lineup.teams.a.map(\.id), b = result.lineup.teams.b.map(\.id)
        guard !a.isEmpty, !b.isEmpty, Set(a).isDisjoint(with: b) else { return }
        var table = levels[result.sport] ?? [:]

        func teamRating(_ ids: [PlayerID]) -> Double {
            ids.map { table[$0]?.rating ?? PlayerLevel.startingRating }.reduce(0, +) / Double(ids.count)
        }
        let expectedA = 1 / (1 + pow(10, (teamRating(b) - teamRating(a)) / 400))
        let total = result.pointsWon.a + result.pointsWon.b
        let shareA = total > 0 ? Double(result.pointsWon.a) / Double(total) : (winner == .a ? 1 : 0)
        let actualA = 0.75 * (winner == .a ? 1 : 0) + 0.25 * shareA

        for (ids, actual, expected) in [(a, actualA, expectedA), (b, 1 - actualA, 1 - expectedA)] {
            for id in ids {
                var level = table[id] ?? PlayerLevel()
                let k: Double = level.matches < 10 ? 48 : 24
                let before = level.level
                level.rating += k * (actual - expected)
                level.matches += 1
                level.recent = Array((level.recent + [level.level - before]).suffix(5))
                level.recentChange = level.recent.reduce(0, +)
                table[id] = level
            }
        }
        levels[result.sport] = table
    }
}
