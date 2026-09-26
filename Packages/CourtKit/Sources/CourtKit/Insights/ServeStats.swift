//
//  ServeStats.swift
//  CourtKit
//
//  Serve statistics straight from the rally log: for every rally the engine
//  knows who served, so "points won on my serve" is exact in both sports
//  and in doubles.
//

import Foundation

public struct ServeStats: Hashable, Codable, Sendable {
    public var pointsServed: Int
    public var pointsWonOnServe: Int
    /// Padel: service games played and held.
    public var serviceGames: Int
    public var serviceGamesHeld: Int

    public init(pointsServed: Int = 0, pointsWonOnServe: Int = 0, serviceGames: Int = 0, serviceGamesHeld: Int = 0) {
        self.pointsServed = pointsServed
        self.pointsWonOnServe = pointsWonOnServe
        self.serviceGames = serviceGames
        self.serviceGamesHeld = serviceGamesHeld
    }

    public var pointsWonPercent: Int? {
        guard pointsServed > 0 else { return nil }
        return Int((Double(pointsWonOnServe) / Double(pointsServed) * 100).rounded())
    }

    public var holdPercent: Int? {
        guard serviceGames > 0 else { return nil }
        return Int((Double(serviceGamesHeld) / Double(serviceGames) * 100).rounded())
    }

    public static func + (lhs: ServeStats, rhs: ServeStats) -> ServeStats {
        ServeStats(
            pointsServed: lhs.pointsServed + rhs.pointsServed,
            pointsWonOnServe: lhs.pointsWonOnServe + rhs.pointsWonOnServe,
            serviceGames: lhs.serviceGames + rhs.serviceGames,
            serviceGamesHeld: lhs.serviceGamesHeld + rhs.serviceGamesHeld
        )
    }

    /// Serve stats for one player slot, or for the whole team when `index`
    /// is nil.
    public static func compute(scorer: MatchScorer, team: Team, index: Int? = nil) -> ServeStats {
        var stats = ServeStats()
        var state = scorer.rules.start()

        func isMine(_ slot: PlayerSlot?) -> Bool {
            guard let slot, slot.team == team else { return false }
            return index == nil || slot.index == index
        }

        for rally in scorer.rallies {
            let before = state.display
            state = state.rallyWon(by: rally.winner)
            let after = state.display
            guard isMine(before.server) else { continue }

            stats.pointsServed += 1
            if rally.winner == team { stats.pointsWonOnServe += 1 }

            // Padel: the server is fixed for a whole game, so the rally that
            // ends a (non-tiebreak) game tells us whether serve was held.
            let isTiebreak = before.phase == .tiebreak || before.phase == .superTiebreak
            if scorer.rules.sport == .padel, !isTiebreak, after.totalGames != before.totalGames {
                stats.serviceGames += 1
                if rally.winner == team { stats.serviceGamesHeld += 1 }
            }
        }
        return stats
    }
}
