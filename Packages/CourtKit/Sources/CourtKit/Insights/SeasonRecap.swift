//
//  SeasonRecap.swift
//  CourtKit
//
//  The season in a handful of cards, Wrapped-style: matches, wins, belts
//  won, your nemesis, your best partner, your hottest streak. Built from
//  confirmed matches only, so it's the same story your friends would tell.
//

import Foundation

/// A calendar year of play.
public struct Season: Hashable, Codable, Sendable, Identifiable {
    public let year: Int

    public init(year: Int) { self.year = year }

    public init(containing date: Date, calendar: Calendar = .current) {
        self.year = calendar.component(.year, from: date)
    }

    public var id: Int { year }
    public var title: String { String(year) }

    public func interval(calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return DateInterval(start: start, end: end)
    }
}

/// Someone who shaped your season, and your record with (or against) them.
public struct RecapPerson: Hashable, Codable, Sendable {
    public let player: PlayerRef
    public let wins: Int
    public let losses: Int

    public var games: Int { wins + losses }
}

public struct SeasonRecap: Hashable, Codable, Sendable {
    public let season: Season
    public let matches: Int
    public let wins: Int
    public let losses: Int
    public let pointsWon: Int
    public let matchesBySport: [Sport: Int]
    /// Belts taken (or created) this season.
    public let beltsWon: Int
    public let titleDefenses: Int
    public let longestReignDays: Int
    /// Most losses against (at least two, and more losses than wins).
    public let nemesis: RecapPerson?
    /// Most wins together (at least two matches).
    public let bestPartner: RecapPerson?
    /// Who you beat most.
    public let favoriteOpponent: RecapPerson?
    public let longestWinStreak: Int
    /// 1–12.
    public let busiestMonth: Int?
    public let busiestMonthMatches: Int
    public let peoplePlayed: Int
    public let tournamentsWon: Int

    public var winRate: Double { matches > 0 ? Double(wins) / Double(matches) : 0 }
    /// Something to show.
    public var isEmpty: Bool { matches == 0 }

    /// - Parameters:
    ///   - results: confirmed matches (any date; the season is picked out).
    ///   - ledger: belts from all confirmed matches.
    public static func compute(
        for me: PlayerID,
        season: Season,
        results: [MatchResult],
        ledger: BeltLedger,
        tournamentsWon: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SeasonRecap {
        let window = season.interval(calendar: calendar)
        let mine = results
            .filter { window.contains($0.date) && $0.winner != nil }
            .sorted(by: BeltLedger.chronological)
            .compactMap { $0.perspective(of: me) }

        var bySport: [Sport: Int] = [:]
        var against: [PlayerID: (ref: PlayerRef, w: Int, l: Int)] = [:]
        var with: [PlayerID: (ref: PlayerRef, w: Int, l: Int)] = [:]
        var months: [Int: Int] = [:]
        var streak = 0, best = 0, points = 0, wins = 0
        var people: Set<PlayerID> = []

        for p in mine {
            bySport[p.result.sport, default: 0] += 1
            months[calendar.component(.month, from: p.result.date), default: 0] += 1
            points += p.pointsFor
            if p.didWin {
                wins += 1
                streak += 1
                best = max(best, streak)
            } else {
                streak = 0
            }
            for o in p.opponents {
                people.insert(o.id)
                var e = against[o.id] ?? (o, 0, 0)
                if p.didWin { e.w += 1 } else { e.l += 1 }
                e.ref = o
                against[o.id] = e
            }
            for partner in p.partners {
                people.insert(partner.id)
                var e = with[partner.id] ?? (partner, 0, 0)
                if p.didWin { e.w += 1 } else { e.l += 1 }
                e.ref = partner
                with[partner.id] = e
            }
        }

        func person(_ e: (ref: PlayerRef, w: Int, l: Int)) -> RecapPerson { RecapPerson(player: e.ref, wins: e.w, losses: e.l) }
        func tiebreak(_ x: (ref: PlayerRef, w: Int, l: Int), _ y: (ref: PlayerRef, w: Int, l: Int)) -> Bool {
            x.ref.id.rawValue.uuidString < y.ref.id.rawValue.uuidString
        }

        let nemesis = against.values
            .filter { $0.l >= 2 && $0.l > $0.w }
            .max { ($0.l - $0.w, $0.l) != ($1.l - $1.w, $1.l) ? ($0.l - $0.w, $0.l) < ($1.l - $1.w, $1.l) : tiebreak($1, $0) }
            .map(person)
        let favorite = against.values
            .filter { $0.w >= 2 }
            .max { ($0.w, -$0.l) != ($1.w, -$1.l) ? ($0.w, -$0.l) < ($1.w, -$1.l) : tiebreak($1, $0) }
            .map(person)
        let partner = with.values
            .filter { $0.w + $0.l >= 2 && $0.w > 0 }
            .max { ($0.w, -$0.l) != ($1.w, -$1.l) ? ($0.w, -$0.l) < ($1.w, -$1.l) : tiebreak($1, $0) }
            .map(person)

        // Belts.
        var beltsWon = 0, defenses = 0, longest = 0
        for belt in ledger.belts(involving: me) {
            for reign in belt.reigns where reign.holder.contains(me) {
                if window.contains(reign.start) { beltsWon += 1 }
                let start = max(reign.start, window.start)
                let end = min(reign.end ?? now, window.end, now)
                if end > start { longest = max(longest, Int(end.timeIntervalSince(start) / 86_400)) }
            }
            defenses += belt.bouts.filter { $0.outcome == .defended && $0.winners.contains(me) && window.contains($0.date) }.count
        }

        let busiest = months.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
        return SeasonRecap(
            season: season, matches: mine.count, wins: wins, losses: mine.count - wins, pointsWon: points,
            matchesBySport: bySport, beltsWon: beltsWon, titleDefenses: defenses, longestReignDays: longest,
            nemesis: nemesis, bestPartner: partner, favoriteOpponent: favorite, longestWinStreak: best,
            busiestMonth: busiest?.key, busiestMonthMatches: busiest?.value ?? 0, peoplePlayed: people.count,
            tournamentsWon: tournamentsWon
        )
    }
}
