//
//  Rivalry.swift
//  CourtKit
//
//  Head-to-head records, opponent watchlists and partner stats, all derived
//  from local match history by player ID.
//

import Foundation

public struct HeadToHead: Hashable, Sendable {
    public let me: PlayerID
    public let opponent: PlayerID
    /// Decided matches where the opponent was across the net, newest first.
    public let matches: [Perspective]

    public var wins: Int { matches.filter(\.didWin).count }
    public var losses: Int { matches.count - wins }
    public var pointDifferential: Int { matches.reduce(0) { $0 + $1.pointDifferential } }

    /// Results of the last five meetings, newest first. `true` = I won.
    public var lastFive: [Bool] { matches.prefix(5).map(\.didWin) }

    /// Who holds the current streak and how long it is.
    public var streak: (winner: PlayerID, count: Int)? {
        guard let first = matches.first else { return nil }
        let count = matches.prefix { $0.didWin == first.didWin }.count
        return (first.didWin ? me : opponent, count)
    }

    /// Smallest point margin; the most recent wins a tie.
    public var closest: Perspective? {
        matches.min { abs($0.pointDifferential) < abs($1.pointDifferential) }
    }

    /// My doubles partners against this opponent, best win rate first.
    public var partners: [PartnerRecord] {
        PartnerRecord.compute(from: matches)
    }

    public static func compute(me: PlayerID, opponent: PlayerID, results: [MatchResult]) -> HeadToHead {
        let meetings = results
            .compactMap { $0.perspective(of: me) }
            .filter { $0.isDecided && $0.opponents.contains { $0.id == opponent } }
            .sorted { $0.result.date > $1.result.date }
        return HeadToHead(me: me, opponent: opponent, matches: meetings)
    }

    public static func == (lhs: HeadToHead, rhs: HeadToHead) -> Bool {
        lhs.me == rhs.me && lhs.opponent == rhs.opponent && lhs.matches == rhs.matches
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(me)
        hasher.combine(opponent)
        hasher.combine(matches)
    }
}

public struct PartnerRecord: Hashable, Sendable, Identifiable {
    public let partner: PlayerRef
    public let wins: Int
    public let played: Int

    public var id: PlayerID { partner.id }
    public var losses: Int { played - wins }
    public var winRate: Double { played > 0 ? Double(wins) / Double(played) : 0 }

    static func compute(from perspectives: [Perspective]) -> [PartnerRecord] {
        var tally: [PlayerID: (ref: PlayerRef, wins: Int, played: Int)] = [:]
        for p in perspectives where p.isDecided {
            for partner in p.partners {
                var entry = tally[partner.id] ?? (partner, 0, 0)
                entry.played += 1
                if p.didWin { entry.wins += 1 }
                tally[partner.id] = entry
            }
        }
        return tally.values
            .map { PartnerRecord(partner: $0.ref, wins: $0.wins, played: $0.played) }
            .sorted {
                if $0.winRate != $1.winRate { return $0.winRate > $1.winRate }
                if $0.played != $1.played { return $0.played > $1.played }
                return $0.partner.displayName < $1.partner.displayName
            }
    }

    /// Every partner I have played doubles with.
    public static func all(for me: PlayerID, results: [MatchResult]) -> [PartnerRecord] {
        compute(from: results.compactMap { $0.perspective(of: me) })
    }
}

/// One row of the opponents "watchlist".
public struct OpponentSummary: Hashable, Sendable, Identifiable {
    public let opponent: PlayerRef
    public let wins: Int
    public let losses: Int
    /// Recent results oldest → newest, for the sparkline. `true` = I won.
    public let recentForm: [Bool]
    public let lastPlayed: Date

    public var id: PlayerID { opponent.id }
    public var played: Int { wins + losses }

    /// Change over the last meeting: +1 won, −1 lost.
    public var trend: Int {
        guard let last = recentForm.last else { return 0 }
        return last ? 1 : -1
    }

    public static func list(for me: PlayerID, results: [MatchResult], formLength: Int = 8) -> [OpponentSummary] {
        var meetings: [PlayerID: (ref: PlayerRef, games: [Perspective])] = [:]
        for result in results {
            guard let p = result.perspective(of: me), p.isDecided else { continue }
            for opponent in p.opponents {
                var entry = meetings[opponent.id] ?? (opponent, [])
                entry.games.append(p)
                // Prefer the newest spelling of the name.
                if result.date >= (entry.games.map(\.result.date).max() ?? .distantPast) {
                    entry.ref = opponent
                }
                meetings[opponent.id] = entry
            }
        }
        return meetings.values.map { entry in
            let sorted = entry.games.sorted { $0.result.date < $1.result.date }
            let wins = sorted.filter(\.didWin).count
            return OpponentSummary(
                opponent: entry.ref,
                wins: wins,
                losses: sorted.count - wins,
                recentForm: sorted.suffix(formLength).map(\.didWin),
                lastPlayed: sorted.last?.result.date ?? .distantPast
            )
        }
        .sorted {
            if $0.lastPlayed != $1.lastPlayed { return $0.lastPlayed > $1.lastPlayed }
            return $0.opponent.displayName < $1.opponent.displayName
        }
    }
}
