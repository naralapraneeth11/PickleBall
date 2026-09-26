//
//  LiveScoreSnapshot.swift
//  CourtKit
//
//  The Live Activity / Dynamic Island payload. Lives in the package so the
//  app (which starts and updates the activity) and the widget extension
//  (which renders it) share one definition.
//

import Foundation

public struct LiveScoreSnapshot: Codable, Hashable, Sendable {
    public var points: TeamPair<String>
    /// Games (pickleball) or games in the current set (padel).
    public var games: TeamPair<Int>
    public var sets: TeamPair<Int>
    /// "11-7 · 9-11" / "6-4 · 3-6" from team A's point of view.
    public var history: String
    public var servingTeam: Team?
    public var call: String
    public var phaseTitle: String
    /// "Match point" etc. for the team facing it.
    public var pressure: String?
    public var pressureTeam: Team?
    public var winner: Team?
    public var updatedAt: Date

    public init(scorer: MatchScorer, updatedAt: Date = Date()) {
        let display = scorer.display
        self.points = display.points
        self.games = display.games
        self.sets = display.sets
        self.history = display.completed.map(\.label).joined(separator: " · ")
        self.servingTeam = display.servingTeam
        self.call = display.call
        self.phaseTitle = display.phaseTitle
        self.winner = display.winner
        self.updatedAt = updatedAt

        let pressures = Team.allCases.compactMap { team in scorer.pressure(for: team).map { (team, $0) } }
        if let top = pressures.max(by: { $0.1 < $1.1 }) {
            self.pressure = top.1.title
            self.pressureTeam = top.0
        } else {
            self.pressure = nil
            self.pressureTeam = nil
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

public struct LiveScoreAttributes: ActivityAttributes, Sendable {
    public typealias ContentState = LiveScoreSnapshot

    public var matchID: UUID
    public var sport: Sport
    public var teamA: String
    public var teamB: String
    public var rulesSummary: String

    public init(matchID: UUID, sport: Sport, teamA: String, teamB: String, rulesSummary: String) {
        self.matchID = matchID
        self.sport = sport
        self.teamA = teamA
        self.teamB = teamB
        self.rulesSummary = rulesSummary
    }

    public func name(of team: Team) -> String { team == .a ? teamA : teamB }
}
#endif
