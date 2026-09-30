//
//  Ladder.swift
//  CourtKit
//
//  The squad ladder: one ranking per squad and sport that you climb by
//  beating people above you. Beat someone higher and you take their rung;
//  everyone in between steps down one. Lose to someone below and you're
//  the one stepping down. Nothing moves when the higher side wins.
//
//  Like belts, the ladder is never stored: it's folded from the squad's
//  confirmed matches, oldest first, so every phone gets the same order.
//  Doubles count too: each winner, best-placed first, jumps the best-placed
//  loser still above them.
//

import Foundation

public struct LadderRung: Identifiable, Hashable, Sendable {
    public let player: PlayerID
    /// 1-based.
    public internal(set) var rank: Int
    /// Rungs gained (positive) or lost in this player's last match.
    public internal(set) var lastMove = 0
    public internal(set) var wins = 0
    public internal(set) var losses = 0
    public internal(set) var lastPlayed: Date?
    /// When this player took the top rung, if they're on it.
    public internal(set) var topSince: Date?

    public var id: PlayerID { player }
}

public enum Ladder {
    /// - Parameters:
    ///   - members: squad members, longest-standing first. New members start
    ///     at the bottom in this order; anyone who left is dropped.
    ///   - results: the squad's confirmed matches in this sport.
    public static func compute(members: [PlayerID], results: [MatchResult]) -> [LadderRung] {
        let memberSet = Set(members)
        var order = members
        var rungs = Dictionary(uniqueKeysWithValues: members.map { ($0, LadderRung(player: $0, rank: 0)) })
        var topSince: Date?

        for result in results.sorted(by: BeltLedger.chronological) {
            guard let winner = result.winner else { continue }
            let winners = result.lineup.teams[winner].map(\.id).filter(memberSet.contains)
            let losers = result.lineup.teams[winner.opponent].map(\.id).filter(memberSet.contains)
            guard !winners.isEmpty, !losers.isEmpty else { continue }
            let before = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            let leader = order.first

            for w in winners.sorted(by: { before[$0]! < before[$1]! }) {
                let current = order.firstIndex(of: w)!
                guard let target = losers.compactMap({ order.firstIndex(of: $0) }).min(), target < current else { continue }
                order.remove(at: current)
                order.insert(w, at: target)
            }

            let after = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            for p in winners + losers {
                rungs[p]?.lastMove = before[p]! - after[p]!
                rungs[p]?.lastPlayed = result.date
                if winners.contains(p) { rungs[p]?.wins += 1 } else { rungs[p]?.losses += 1 }
            }
            if order.first != leader { topSince = result.date }
        }

        return order.enumerated().map { index, player in
            var rung = rungs[player]!
            rung.rank = index + 1
            if index == 0 { rung.topSince = topSince }
            return rung
        }
    }
}
