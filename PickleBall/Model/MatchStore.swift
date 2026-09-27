//
//  MatchStore.swift
//  PickleBall
//
//  Read model over SwiftData match records. Exposes finished matches as
//  CourtKit `MatchResult`s (for head-to-head, form and rivalries) and as
//  `StoredMatch` rows seen from the device owner's side (for stats lists).
//  "Is this my match?" is answered by player ID, never by first name.
//

import Foundation
import Combine
import SwiftData
import CourtKit

struct MatchGameScore: Codable, Equatable, Hashable {
    let myPoints: Int
    let opponentPoints: Int
}

/// A finished match from the device owner's point of view.
struct StoredMatch: Identifiable, Equatable, Hashable {
    let id: UUID
    var matchID: UUID? { id }
    let sport: Sport
    let date: Date
    let opponents: [PlayerRef]
    let partners: [PlayerRef]
    let didWin: Bool
    /// Games (pickleball) or sets (padel).
    let myScore: Int
    let opponentScore: Int
    let gameScores: [MatchGameScore]?
    let pointsFor: Int
    let pointsAgainst: Int
    let servePointsPlayed: Int?
    let servePointsWon: Int?

    var opponent: String {
        let names = opponents.map(\.displayName)
        return names.isEmpty ? "Opponent" : names.joined(separator: " / ")
    }

    var serveHoldPercent: Int? {
        guard let played = servePointsPlayed, played > 0, let won = servePointsWon else { return nil }
        return Int((Double(won) / Double(played) * 100).rounded())
    }
}

@MainActor
final class MatchStore: ObservableObject {
    static let shared = MatchStore()

    /// Every finished match that isn't disputed, newest first.
    @Published private(set) var results: [MatchResult] = []
    /// Matches both sides agreed to (and ones against guests): what belts
    /// are built from.
    @Published private(set) var confirmedResults: [MatchResult] = []
    /// The Belt, derived from confirmed matches.
    @Published private(set) var belts = BeltLedger()
    /// Finished matches the device owner played, newest first.
    @Published private(set) var matches: [StoredMatch] = []
    /// Matches paused mid-way that can be resumed, newest first.
    @Published private(set) var parked: [MatchSetup] = []

    private var context: ModelContext { AppDatabase.context }

    private init() {
        reload()
    }

    var me: PlayerRef { PlayerDirectory.shared.me }

    func reload() {
        let completed = MatchStatus.completed.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.statusRaw == completed },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let records = ((try? context.fetch(descriptor)) ?? []).filter { $0.confirmation != .disputed }
        results = records.compactMap(\.result)
        confirmedResults = records.filter { $0.confirmation == .confirmed }.compactMap(\.result)
        belts = BeltLedger.compute(confirmedResults)

        let meID = me.id
        matches = records.compactMap { Self.storedMatch(from: $0, me: meID) }

        let parkedRaw = MatchStatus.parked.rawValue
        let parkedDescriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.statusRaw == parkedRaw },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        parked = ((try? context.fetch(parkedDescriptor)) ?? []).compactMap(\.setup)
    }

    func record(id: UUID) -> MatchRecord? {
        let raw = id
        var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.id == raw })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The local match recorded for a squad tournament fixture.
    func matchID(forFixture fixtureID: UUID) -> UUID? {
        let raw: UUID? = fixtureID
        var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.tournamentFixtureID == raw })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.id
    }

    func delete(matchID: UUID) {
        guard let record = record(id: matchID) else { return }
        context.delete(record)
        AppDatabase.save()
        reload()
    }

    private static func storedMatch(from record: MatchRecord, me: PlayerID) -> StoredMatch? {
        guard let result = record.result, let perspective = result.perspective(of: me), perspective.isDecided else {
            return nil
        }
        let team = perspective.team

        var served: Int?
        var servedWon: Int?
        if let rules = record.rules, let lineup = record.lineup,
           let index = lineup.teams[team].firstIndex(where: { $0.id == me }) {
            let scorer = MatchScorer(rules: rules, rallies: record.rallyLog)
            let stats = ServeStats.compute(scorer: scorer, team: team, index: index)
            served = stats.pointsServed
            servedWon = stats.pointsWonOnServe
        }

        let units = perspective.orientedUnits
        return StoredMatch(
            id: record.id,
            sport: record.sport,
            date: record.startedAt,
            opponents: perspective.opponents,
            partners: perspective.partners,
            didWin: perspective.didWin,
            myScore: perspective.matchScoreFor,
            opponentScore: perspective.matchScoreAgainst,
            gameScores: units.isEmpty ? nil : units.map { MatchGameScore(myPoints: $0.score.a, opponentPoints: $0.score.b) },
            pointsFor: perspective.pointsFor,
            pointsAgainst: perspective.pointsAgainst,
            servePointsPlayed: served,
            servePointsWon: servedWon
        )
    }

    // MARK: - Device-owner stats

    func myMatches(sport: Sport? = nil) -> [StoredMatch] {
        guard let sport else { return matches }
        return matches.filter { $0.sport == sport }
    }

    func totalWins(sport: Sport? = nil) -> Int {
        myMatches(sport: sport).filter(\.didWin).count
    }

    func winPercentage(sport: Sport? = nil) -> Double {
        let list = myMatches(sport: sport)
        guard !list.isEmpty else { return 0 }
        return Double(list.filter(\.didWin).count) / Double(list.count) * 100
    }

    /// Average points scored per game (pickleball) or per set (padel).
    func averagePointsScored(sport: Sport? = nil) -> Double {
        var points = 0
        var units = 0
        for match in myMatches(sport: sport) {
            if let games = match.gameScores, !games.isEmpty {
                points += games.reduce(0) { $0 + $1.myPoints }
                units += games.count
            }
        }
        return units > 0 ? Double(points) / Double(units) : 0
    }

    func bestWinScore(sport: Sport? = nil) -> String {
        var best: MatchGameScore?
        var bestDiff = Int.min
        for match in myMatches(sport: sport) where match.didWin {
            for game in match.gameScores ?? [MatchGameScore(myPoints: match.myScore, opponentPoints: match.opponentScore)] {
                let diff = game.myPoints - game.opponentPoints
                if diff > bestDiff || (diff == bestDiff && game.myPoints > (best?.myPoints ?? 0)) {
                    bestDiff = diff
                    best = game
                }
            }
        }
        guard let best else { return "—" }
        return "\(best.myPoints)-\(best.opponentPoints)"
    }

    func recentMatches(limit: Int = 20, sport: Sport? = nil) -> [StoredMatch] {
        Array(myMatches(sport: sport).prefix(limit))
    }

    func serveHoldStats(sport: Sport? = nil) -> (played: Int, won: Int, percent: Int?) {
        let list = myMatches(sport: sport)
        let played = list.reduce(0) { $0 + ($1.servePointsPlayed ?? 0) }
        let won = list.reduce(0) { $0 + ($1.servePointsWon ?? 0) }
        guard played > 0 else { return (0, 0, nil) }
        return (played, won, Int((Double(won) / Double(played) * 100).rounded()))
    }
}
