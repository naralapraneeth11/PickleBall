//
//  MatchResult.swift
//  CourtKit
//
//  A finished match reduced to what history screens need, keyed by player
//  IDs. Built from a rally log (new matches) or from imported legacy scores.
//

import Foundation

public struct MatchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sport: Sport
    public var date: Date
    public var lineup: Lineup
    public var winner: Team?
    /// Games (pickleball) or sets (padel), oldest first.
    public var units: [CompletedUnit]
    /// Rallies won per team. For legacy imports without a log this is the sum
    /// of game points.
    public var pointsWon: TeamPair<Int>
    /// Games (pickleball) or sets (padel) won.
    public var matchScore: TeamPair<Int>

    public init(
        id: UUID,
        sport: Sport,
        date: Date,
        lineup: Lineup,
        winner: Team?,
        units: [CompletedUnit],
        pointsWon: TeamPair<Int>,
        matchScore: TeamPair<Int>
    ) {
        self.id = id
        self.sport = sport
        self.date = date
        self.lineup = lineup
        self.winner = winner
        self.units = units
        self.pointsWon = pointsWon
        self.matchScore = matchScore
    }

    public init(id: UUID, date: Date, lineup: Lineup, scorer: MatchScorer) {
        let display = scorer.display
        self.init(
            id: id,
            sport: scorer.rules.sport,
            date: date,
            lineup: lineup,
            winner: scorer.winner,
            units: display.completed,
            pointsWon: scorer.ralliesWon,
            matchScore: display.matchScore
        )
    }

    public func perspective(of player: PlayerID) -> Perspective? {
        guard let team = lineup.team(of: player) else { return nil }
        return Perspective(result: self, team: team, player: player)
    }

    /// "11-7, 9-11, 11-4" from team A's point of view.
    public var scoreLine: String {
        units.map(\.label).joined(separator: ", ")
    }
}

/// A match seen from one player's side.
public struct Perspective: Hashable, Sendable {
    public let result: MatchResult
    public let team: Team
    public let player: PlayerID

    public var didWin: Bool { result.winner == team }
    public var isDecided: Bool { result.winner != nil }
    public var partners: [PlayerRef] { result.lineup.teams[team].filter { $0.id != player } }
    public var opponents: [PlayerRef] { result.lineup.teams[team.opponent] }
    public var pointsFor: Int { result.pointsWon[team] }
    public var pointsAgainst: Int { result.pointsWon[team.opponent] }
    public var pointDifferential: Int { pointsFor - pointsAgainst }
    public var matchScoreFor: Int { result.matchScore[team] }
    public var matchScoreAgainst: Int { result.matchScore[team.opponent] }

    /// Share of points won, 0…1, or nil when no points were recorded.
    public var pointShare: Double? {
        let total = pointsFor + pointsAgainst
        guard total > 0 else { return nil }
        return Double(pointsFor) / Double(total)
    }

    /// Units oriented so `a` is this player's side.
    public var orientedUnits: [CompletedUnit] {
        guard team == .b else { return result.units }
        return result.units.map {
            CompletedUnit(score: $0.score.swapped, tiebreak: $0.tiebreak?.swapped, isSuperTiebreak: $0.isSuperTiebreak)
        }
    }

    /// "11-7, 9-11" from this player's point of view.
    public var scoreLine: String { orientedUnits.map(\.label).joined(separator: ", ") }
}
