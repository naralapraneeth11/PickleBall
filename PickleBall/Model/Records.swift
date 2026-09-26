//
//  Records.swift
//  PickleBall
//
//  SwiftData schema. Matches store their rally log, so every score, stat
//  and head-to-head record can be rebuilt by replaying it through CourtKit.
//  Players are always referenced by ID; names are presentation.
//

import Foundation
import SwiftData
import CourtKit

// MARK: - Player

@Model
final class PlayerRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var displayName: String
    var createdAt: Date
    var lastPlayedAt: Date?
    /// The device owner. Exactly one record has this set.
    var isLocalUser: Bool

    init(id: UUID = UUID(), kind: PlayerKind, displayName: String, isLocalUser: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.displayName = displayName
        self.createdAt = createdAt
        self.isLocalUser = isLocalUser
    }

    var kind: PlayerKind { PlayerKind(rawValue: kindRaw) ?? .guest }

    var ref: PlayerRef {
        PlayerRef(id: PlayerID(rawValue: id), kind: kind, displayName: displayName)
    }
}

// MARK: - Match

enum MatchStatus: String, Codable {
    /// Being scored right now.
    case live
    /// Paused mid-match; can be resumed.
    case parked
    case completed
    case abandoned
}

@Model
final class MatchRecord {
    @Attribute(.unique) var id: UUID
    var sportRaw: String
    var rulesData: Data
    /// Lineup snapshot (IDs plus the names at the time of the match).
    var lineupData: Data
    /// Every participant, for filtering without decoding the lineup.
    var playerIDs: [UUID]
    var statusRaw: String
    var hostRaw: String
    var startedAt: Date
    var endedAt: Date?

    // Denormalised summary, refreshed whenever the log changes.
    var winnerRaw: Int?
    var matchScoreA: Int
    var matchScoreB: Int
    var pointsA: Int
    var pointsB: Int
    /// `[CompletedUnit]` JSON. Authoritative only for legacy imports, which
    /// have no rally log.
    var unitsData: Data?
    var isLegacyImport: Bool
    /// Serve points carried over from the pre-rally-log format.
    var legacyServePointsPlayed: Int?
    var legacyServePointsWon: Int?

    var tournamentID: UUID?
    var tournamentFixtureID: UUID?

    /// `WorkoutSummary` JSON from the Watch, when one was recorded.
    var workoutData: Data?

    @Relationship(deleteRule: .cascade, inverse: \RallyRecord.match)
    var rallies: [RallyRecord] = []

    init(setup: MatchSetup, status: MatchStatus = .live) {
        self.id = setup.matchID
        self.sportRaw = setup.rules.sport.rawValue
        self.rulesData = (try? JSONEncoder().encode(setup.rules)) ?? Data()
        self.lineupData = (try? JSONEncoder().encode(setup.lineup)) ?? Data()
        self.playerIDs = setup.lineup.allPlayers.map(\.id.rawValue)
        self.statusRaw = status.rawValue
        self.hostRaw = setup.host.rawValue
        self.startedAt = setup.startedAt
        self.matchScoreA = 0
        self.matchScoreB = 0
        self.pointsA = 0
        self.pointsB = 0
        self.isLegacyImport = false
        self.tournamentFixtureID = setup.tournamentMatchID
    }

    var sport: Sport { Sport(rawValue: sportRaw) ?? .pickleball }
    var status: MatchStatus {
        get { MatchStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }
    var rules: MatchRules? { try? JSONDecoder().decode(MatchRules.self, from: rulesData) }
    var lineup: Lineup? { try? JSONDecoder().decode(Lineup.self, from: lineupData) }
    var winner: Team? { winnerRaw.flatMap(Team.init(rawValue:)) }

    var setup: MatchSetup? {
        guard let rules, let lineup else { return nil }
        return MatchSetup(
            matchID: id,
            rules: rules,
            lineup: lineup,
            startedAt: startedAt,
            host: DeviceRole(rawValue: hostRaw) ?? .phone,
            tournamentMatchID: tournamentFixtureID
        )
    }

    /// The rally log in order.
    var rallyLog: [Rally] {
        rallies
            .sorted { $0.sequence < $1.sequence }
            .compactMap { record in record.team.map { Rally(winner: $0, at: record.at) } }
    }

    var workout: WorkoutSummary? {
        get { workoutData.flatMap { try? JSONDecoder().decode(WorkoutSummary.self, from: $0) } }
        set { workoutData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Replaces the stored log and refreshes the summary columns.
    func apply(log: [Rally], in context: ModelContext) {
        let existing = rallies.sorted { $0.sequence < $1.sequence }
        let sharedPrefix = zip(existing, log).prefix { record, rally in
            record.team == rally.winner && record.at == rally.at
        }.count

        for record in existing.dropFirst(sharedPrefix) {
            context.delete(record)
        }
        rallies.removeAll { $0.sequence > sharedPrefix }
        for (offset, rally) in log.enumerated().dropFirst(sharedPrefix) {
            let record = RallyRecord(sequence: offset + 1, winner: rally.winner, at: rally.at)
            record.match = self
            rallies.append(record)
        }

        guard let rules else { return }
        refreshSummary(from: MatchScorer(rules: rules, rallies: log))
    }

    func refreshSummary(from scorer: MatchScorer) {
        let display = scorer.display
        winnerRaw = scorer.winner?.rawValue
        matchScoreA = display.matchScore.a
        matchScoreB = display.matchScore.b
        let points = scorer.ralliesWon
        pointsA = points.a
        pointsB = points.b
        unitsData = try? JSONEncoder().encode(display.completed)
    }

    var units: [CompletedUnit] {
        unitsData.flatMap { try? JSONDecoder().decode([CompletedUnit].self, from: $0) } ?? []
    }

    /// History-screen view of a finished match.
    var result: MatchResult? {
        guard let lineup else { return nil }
        return MatchResult(
            id: id,
            sport: sport,
            date: startedAt,
            lineup: lineup,
            winner: winner,
            units: units,
            pointsWon: TeamPair(a: pointsA, b: pointsB),
            matchScore: TeamPair(a: matchScoreA, b: matchScoreB)
        )
    }
}

@Model
final class RallyRecord {
    /// 1-based rally number within the match.
    var sequence: Int
    var winnerRaw: Int
    var at: Date
    var match: MatchRecord?

    init(sequence: Int, winner: Team, at: Date) {
        self.sequence = sequence
        self.winnerRaw = winner.rawValue
        self.at = at
    }

    var team: Team? { Team(rawValue: winnerRaw) }
}

// MARK: - Tournament

@Model
final class TournamentRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String?
    var sportRaw: String
    var isSingles: Bool
    var bestOf: Int
    var targetScore: Int
    var participantCount: Int
    var shuffledOrder: [UUID]
    /// `[TournamentParticipant]` JSON: each label with its player IDs.
    var participantsData: Data

    @Relationship(deleteRule: .cascade, inverse: \TournamentFixtureRecord.tournament)
    var fixtures: [TournamentFixtureRecord] = []

    init(id: UUID, createdAt: Date, sport: Sport) {
        self.id = id
        self.createdAt = createdAt
        self.sportRaw = sport.rawValue
        self.isSingles = true
        self.bestOf = 1
        self.targetScore = 11
        self.participantCount = 0
        self.shuffledOrder = []
        self.participantsData = Data()
    }
}

@Model
final class TournamentFixtureRecord {
    var id: UUID
    var order: Int
    var player1: String
    var player2: String
    var player1GamesWon: Int?
    var player2GamesWon: Int?
    var gameScoresData: Data?
    var matchRecordID: UUID?
    var tournament: TournamentRecord?

    init(id: UUID, order: Int, player1: String, player2: String) {
        self.id = id
        self.order = order
        self.player1 = player1
        self.player2 = player2
    }
}

// MARK: - Watch workouts

/// What the Watch measured during a match (shared CourtKit type).
typealias WorkoutSummary = WorkoutReport

/// A Watch workout session. Linked to a match when one was scored.
@Model
final class WorkoutSessionRecord {
    @Attribute(.unique) var id: UUID
    var matchID: UUID?
    var date: Date
    var summaryData: Data
    /// Legacy fatigue fraction from pre-zone versions; kept for history only.
    var legacyFatigueOnset: Double?

    init(id: UUID = UUID(), matchID: UUID?, date: Date, summary: WorkoutSummary) {
        self.id = id
        self.matchID = matchID
        self.date = date
        self.summaryData = (try? JSONEncoder().encode(summary)) ?? Data()
    }

    var summary: WorkoutSummary? {
        get { try? JSONDecoder().decode(WorkoutSummary.self, from: summaryData) }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } ?? summaryData }
    }
}
