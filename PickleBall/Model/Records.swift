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
import CourtNet

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

/// Where a finished match stands with the other side.
enum MatchConfirmation: String, Codable {
    /// Not on the server yet (offline, or just finished).
    case local
    /// Waiting for the other side to confirm.
    case pending
    case confirmed
    case disputed

    init(_ status: ConfirmationStatus) {
        switch status {
        case .pending: self = .pending
        case .confirmed: self = .confirmed
        case .disputed: self = .disputed
        }
    }
}

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
    /// `[CompletedUnit]` JSON, cached from the rally log.
    var unitsData: Data?

    var tournamentID: UUID?
    var tournamentFixtureID: UUID?

    /// `WorkoutSummary` JSON from the Watch, when one was recorded.
    var workoutData: Data?

    // Phase 2: shared matches.
    var sourceRaw: String = MatchSource.phone.rawValue
    var confirmationRaw: String = MatchConfirmation.local.rawValue
    /// The account that recorded it (nil before sign-in).
    var createdByID: UUID?
    var squadID: UUID?
    var calloutID: UUID?
    /// `CourtTag` JSON.
    var courtData: Data?
    /// Server `updated_at` of the copy we last saw.
    var remoteUpdatedAt: Date?
    /// The account whose history this is on this phone; nil for matches
    /// scored signed out. See `AccountScope`.
    var ownerAccountID: UUID?
    /// My confirm or dispute, sent but not yet answered by the server
    /// ("agree" or "dispute"). Until then the result isn't final.
    var myAnswerRaw: String?

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
        self.tournamentFixtureID = setup.tournamentMatchID
        self.sourceRaw = (setup.host == .watch ? MatchSource.watch : MatchSource.phone).rawValue
        self.ownerAccountID = AccountScope.current
    }

    /// A match typed in after it was played.
    convenience init(entered score: EnteredScore, rules: MatchRules, lineup: Lineup, playedAt: Date, context: MatchContext) {
        self.init(setup: MatchSetup(rules: rules, lineup: lineup, startedAt: playedAt, host: .phone), status: .completed)
        sourceRaw = MatchSource.entered.rawValue
        endedAt = playedAt
        winnerRaw = score.winner.rawValue
        matchScoreA = score.matchScore.a
        matchScoreB = score.matchScore.b
        pointsA = score.pointsWon.a
        pointsB = score.pointsWon.b
        unitsData = try? JSONEncoder().encode(score.units)
        matchContext = context
    }

    var source: MatchSource {
        get { MatchSource(rawValue: sourceRaw) ?? .phone }
        set { sourceRaw = newValue.rawValue }
    }

    var confirmation: MatchConfirmation {
        get { MatchConfirmation(rawValue: confirmationRaw) ?? .local }
        set { confirmationRaw = newValue.rawValue }
    }

    var court: CourtTag? {
        get { courtData.flatMap { try? JSONDecoder().decode(CourtTag.self, from: $0) } }
        set { courtData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Squad, tournament, call out and court: where the match belongs.
    var matchContext: MatchContext {
        get {
            MatchContext(court: court, squadID: squadID, tournamentID: tournamentID,
                         fixtureID: tournamentFixtureID, calloutID: calloutID)
        }
        set {
            court = newValue.court
            squadID = newValue.squadID
            tournamentID = newValue.tournamentID
            tournamentFixtureID = newValue.fixtureID
            calloutID = newValue.calloutID
        }
    }

    /// Everything the server needs to store this match.
    var uploadRequest: SaveMatchRequest? {
        guard let rules, let lineup, winner != nil else { return nil }
        if source == .entered {
            let score = EnteredScore(units: units, winner: winner ?? .a,
                                     matchScore: TeamPair(a: matchScoreA, b: matchScoreB),
                                     pointsWon: TeamPair(a: pointsA, b: pointsB))
            return MatchWire.payload(id: id, rules: rules, lineup: lineup, entered: score, playedAt: startedAt, context: matchContext)
        }
        return MatchWire.payload(id: id, rules: rules, lineup: lineup, rallies: rallyLog, startedAt: startedAt,
                                 endedAt: endedAt, source: source, context: matchContext, workout: workout)
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
            // Appending sets the inverse (`record.match`) too.
            rallies.append(RallyRecord(sequence: offset + 1, winner: rally.winner, at: rally.at))
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
            matchScore: TeamPair(a: matchScoreA, b: matchScoreB),
            squadID: squadID
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
    /// The account signed in when it was recorded; nil when signed out.
    var ownerAccountID: UUID?

    init(id: UUID = UUID(), matchID: UUID?, date: Date, summary: WorkoutSummary) {
        self.id = id
        self.matchID = matchID
        self.date = date
        self.summaryData = (try? JSONEncoder().encode(summary)) ?? Data()
        self.ownerAccountID = AccountScope.current
    }

    var summary: WorkoutSummary? {
        get { try? JSONDecoder().decode(WorkoutSummary.self, from: summaryData) }
        set { summaryData = newValue.flatMap { try? JSONEncoder().encode($0) } ?? summaryData }
    }
}
