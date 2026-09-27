//
//  MatchWire.swift
//  CourtNetCore
//
//  Matches between CourtKit and the database: the save_match payload the
//  scorer uploads, and the MatchResult every phone rebuilds from rows.
//

import Foundation
import CourtKit

/// One player in an uploaded match.
public struct ParticipantPayload: Codable, Hashable, Sendable {
    public var playerID: UUID
    public var team: Team
    public var slot: Int
    public var kind: PlayerKind
    public var displayName: String

    public init(playerID: UUID, team: Team, slot: Int, kind: PlayerKind, displayName: String) {
        self.playerID = playerID
        self.team = team
        self.slot = slot
        self.kind = kind
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case team, slot, kind
        case playerID = "player_id"
        case displayName = "display_name"
    }
}

/// The `m` argument of save_match.
public struct MatchPayload: Codable, Hashable, Sendable {
    public var id: UUID
    public var sport: Sport
    public var rules: MatchRules
    public var source: MatchSource
    public var startedAt: Date
    public var endedAt: Date?
    public var winnerTeam: Team?
    public var matchScore: [Int]
    public var points: [Int]
    public var units: [CompletedUnit]
    public var rallyWinners: String?
    public var rallyOffsets: [Double]?
    public var court: CourtTag?
    public var squadID: UUID?
    public var tournamentID: UUID?
    public var fixtureID: UUID?
    public var calloutID: UUID?
    public var workout: WorkoutReport?

    enum CodingKeys: String, CodingKey {
        case id, sport, rules, source, points, units, court, workout
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerTeam = "winner_team"
        case matchScore = "match_score"
        case rallyWinners = "rally_winners"
        case rallyOffsets = "rally_offsets"
        case squadID = "squad_id"
        case tournamentID = "tournament_id"
        case fixtureID = "fixture_id"
        case calloutID = "callout_id"
    }

    public func encode(to encoder: Encoder) throws {
        // Leave optional keys out entirely: save_match checks for presence.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sport, forKey: .sport)
        try c.encode(rules, forKey: .rules)
        try c.encode(source, forKey: .source)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encodeIfPresent(winnerTeam, forKey: .winnerTeam)
        try c.encode(matchScore, forKey: .matchScore)
        try c.encode(points, forKey: .points)
        try c.encode(units, forKey: .units)
        try c.encodeIfPresent(rallyWinners, forKey: .rallyWinners)
        try c.encodeIfPresent(rallyOffsets, forKey: .rallyOffsets)
        try c.encodeIfPresent(court, forKey: .court)
        try c.encodeIfPresent(squadID, forKey: .squadID)
        try c.encodeIfPresent(tournamentID, forKey: .tournamentID)
        try c.encodeIfPresent(fixtureID, forKey: .fixtureID)
        try c.encodeIfPresent(calloutID, forKey: .calloutID)
        try c.encodeIfPresent(workout, forKey: .workout)
    }
}

/// Everything save_match takes, in its argument names.
public struct SaveMatchRequest: Codable, Hashable, Sendable {
    public var m: MatchPayload
    public var participants: [ParticipantPayload]
    public var events: [ChatEvent]

    public init(m: MatchPayload, participants: [ParticipantPayload], events: [ChatEvent] = []) {
        self.m = m
        self.participants = participants
        self.events = events
    }
}

public enum MatchWire {
    /// Upload payload for a match scored point by point (Watch or phone).
    public static func payload(
        id: UUID,
        rules: MatchRules,
        lineup: Lineup,
        rallies: [Rally],
        startedAt: Date,
        endedAt: Date?,
        source: MatchSource,
        context: MatchContext = MatchContext(),
        workout: WorkoutReport? = nil
    ) -> SaveMatchRequest {
        let scorer = MatchScorer(rules: rules, rallies: rallies)
        let display = scorer.display
        let m = MatchPayload(
            id: id, sport: rules.sport, rules: rules, source: source,
            startedAt: startedAt, endedAt: endedAt, winnerTeam: scorer.winner,
            matchScore: [display.matchScore.a, display.matchScore.b],
            points: [scorer.ralliesWon.a, scorer.ralliesWon.b],
            units: display.completed,
            rallyWinners: String(scorer.rallies.map(\.winner.code)),
            rallyOffsets: scorer.rallies.map { ($0.at.timeIntervalSince(startedAt) * 10).rounded() / 10 },
            court: context.court, squadID: context.squadID, tournamentID: context.tournamentID,
            fixtureID: context.fixtureID, calloutID: context.calloutID, workout: workout
        )
        return SaveMatchRequest(m: m, participants: participants(lineup), events: context.events)
    }

    /// Upload payload for a score typed in after the match.
    public static func payload(
        id: UUID,
        rules: MatchRules,
        lineup: Lineup,
        entered: EnteredScore,
        playedAt: Date,
        context: MatchContext = MatchContext()
    ) -> SaveMatchRequest {
        let m = MatchPayload(
            id: id, sport: rules.sport, rules: rules, source: .entered,
            startedAt: playedAt, endedAt: playedAt, winnerTeam: entered.winner,
            matchScore: [entered.matchScore.a, entered.matchScore.b],
            points: [entered.pointsWon.a, entered.pointsWon.b],
            units: entered.units,
            court: context.court, squadID: context.squadID, tournamentID: context.tournamentID,
            fixtureID: context.fixtureID, calloutID: context.calloutID
        )
        return SaveMatchRequest(m: m, participants: participants(lineup), events: context.events)
    }

    static func participants(_ lineup: Lineup) -> [ParticipantPayload] {
        Team.allCases.flatMap { team in
            lineup.teams[team].enumerated().map { slot, player in
                ParticipantPayload(playerID: player.id.rawValue, team: team, slot: slot, kind: player.kind, displayName: player.displayName)
            }
        }
    }

    /// The lineup of a downloaded match. Players the viewer can't see (a
    /// removed friend's guest, say) show as "Player".
    public static func lineup(participants: [ParticipantRow], players: [UUID: PlayerRow]) -> Lineup {
        func side(_ team: Team) -> [PlayerRef] {
            participants
                .filter { $0.team == team }
                .sorted { $0.slot < $1.slot }
                .map { p in
                    let row = players[p.playerID]
                    // A claimed guest counts as the account that claimed it.
                    if let row, let owner = row.claimedBy {
                        return PlayerRef(id: PlayerID(rawValue: owner), kind: .user, displayName: row.displayName)
                    }
                    return PlayerRef(id: PlayerID(rawValue: p.playerID), kind: row?.kind ?? .guest, displayName: row?.displayName ?? "Player")
                }
        }
        return Lineup(teamA: side(.a), teamB: side(.b))
    }

    /// The rally log, when the match was scored point by point.
    public static func rallies(_ row: MatchRow) -> [Rally]? {
        guard let winners = row.rallyWinners, !winners.isEmpty else { return nil }
        let offsets = row.rallyOffsets ?? []
        return winners.enumerated().compactMap { index, code in
            guard let team = Team(code: code) else { return nil }
            let offset = offsets.indices.contains(index) ? offsets[index] : 0
            return Rally(winner: team, at: row.startedAt.addingTimeInterval(offset))
        }
    }

    public static func result(_ row: MatchRow, lineup: Lineup) -> MatchResult {
        MatchResult(
            id: row.id,
            sport: row.sport,
            date: row.startedAt,
            lineup: lineup,
            winner: row.winnerTeam,
            units: row.units,
            pointsWon: TeamPair(a: row.points.first ?? 0, b: row.points.dropFirst().first ?? 0),
            matchScore: TeamPair(a: row.matchScore.first ?? 0, b: row.matchScore.dropFirst().first ?? 0),
            squadID: row.squadID
        )
    }
}

/// Where a match belongs besides its players.
public struct MatchContext: Hashable, Sendable {
    public var court: CourtTag?
    public var squadID: UUID?
    public var tournamentID: UUID?
    public var fixtureID: UUID?
    public var calloutID: UUID?
    /// Chat events to post if the match is confirmed straight away.
    public var events: [ChatEvent]

    public init(court: CourtTag? = nil, squadID: UUID? = nil, tournamentID: UUID? = nil, fixtureID: UUID? = nil,
                calloutID: UUID? = nil, events: [ChatEvent] = []) {
        self.court = court
        self.squadID = squadID
        self.tournamentID = tournamentID
        self.fixtureID = fixtureID
        self.calloutID = calloutID
        self.events = events
    }
}
