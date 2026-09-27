//
//  MatchScorer.swift
//  CourtKit
//
//  The rally log is the source of truth. State is a fold of the log over the
//  engine, so undo is "replay the log minus the last rally" and a full
//  point-by-point history comes for free.
//

import Foundation

public struct Rally: Hashable, Codable, Sendable {
    public var winner: Team
    public var at: Date

    public init(winner: Team, at: Date = Date()) {
        self.winner = winner
        self.at = at
    }
}

/// Pressure the next rally carries for one team.
public enum Pressure: Int, Hashable, Sendable, Comparable {
    case gamePoint = 1
    case setPoint = 2
    case matchPoint = 3

    public static func < (lhs: Pressure, rhs: Pressure) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .gamePoint: return "Game point"
        case .setPoint: return "Set point"
        case .matchPoint: return "Match point"
        }
    }
}

/// Something worth reacting to (haptics, sound, animation) after a rally.
public enum ScoreEvent: Hashable, Sendable {
    case point(Team)
    case sideOut(to: Team)
    case secondServer
    case gameWon(Team)
    case setWon(Team)
    case matchWon(Team)
    case changeEnds
    case tiebreakStarted
    case pressure(Pressure, Team)
}

public struct MatchScorer: Equatable, Sendable {
    public let rules: MatchRules
    public private(set) var rallies: [Rally]
    public private(set) var state: ScoreState

    public init(rules: MatchRules, rallies: [Rally] = []) {
        self.rules = rules
        self.rallies = []
        self.state = rules.start()
        for rally in rallies where state.winner == nil {
            self.rallies.append(rally)
            state = state.rallyWon(by: rally.winner)
        }
    }

    public var display: ScoreDisplay { state.display }
    public var winner: Team? { state.winner }
    public var isFinished: Bool { state.winner != nil }
    public var canUndo: Bool { !rallies.isEmpty }

    /// Records a rally. Ignored (returns no events) once the match is over.
    @discardableResult
    public mutating func recordRally(wonBy team: Team, at date: Date = Date()) -> [ScoreEvent] {
        guard !isFinished else { return [] }
        let before = display
        rallies.append(Rally(winner: team, at: date))
        state = state.rallyWon(by: team)
        return Self.events(from: before, to: display, rallyWinner: team) + pressureEvents()
    }

    /// Removes the last rally and rebuilds state by replaying the rest.
    @discardableResult
    public mutating func undo() -> Rally? {
        guard let last = rallies.popLast() else { return nil }
        state = Self.replay(rules, rallies)
        return last
    }

    public static func replay(_ rules: MatchRules, _ rallies: [Rally]) -> ScoreState {
        rallies.reduce(rules.start()) { $0.rallyWon(by: $1.winner) }
    }

    /// Highest pressure `team` faces on the next rally, if any.
    public func pressure(for team: Team) -> Pressure? {
        guard !isFinished else { return nil }
        let before = display
        let after = state.rallyWon(by: team).display
        if after.winner == team { return .matchPoint }
        if after.sets[team] > before.sets[team] { return .setPoint }
        if after.totalGames[team] > before.totalGames[team] { return .gamePoint }
        return nil
    }

    /// Every rally with the display that preceded it: the input for serve
    /// statistics and point-by-point timelines.
    public func timeline() -> [(before: ScoreDisplay, rally: Rally)] {
        var current = rules.start()
        var result: [(before: ScoreDisplay, rally: Rally)] = []
        result.reserveCapacity(rallies.count)
        for rally in rallies {
            result.append((current.display, rally))
            current = current.rallyWon(by: rally.winner)
        }
        return result
    }

    /// Rallies won per team.
    public var ralliesWon: TeamPair<Int> {
        rallies.reduce(into: TeamPair<Int>.zero) { $0[$1.winner] += 1 }
    }

    private func pressureEvents() -> [ScoreEvent] {
        Team.allCases.compactMap { team in
            pressure(for: team).map { ScoreEvent.pressure($0, team) }
        }
    }

    static func events(from before: ScoreDisplay, to after: ScoreDisplay, rallyWinner team: Team) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        let gameWon = after.totalGames[team] > before.totalGames[team]

        if gameWon || after.points != before.points {
            events.append(.point(team))
        }
        if gameWon { events.append(.gameWon(team)) }
        if after.sets[team] > before.sets[team] { events.append(.setWon(team)) }
        if let winner = after.winner, before.winner == nil { events.append(.matchWon(winner)) }

        if !gameWon, after.winner == nil, let serving = after.servingTeam {
            if serving != before.servingTeam {
                events.append(.sideOut(to: serving))
            } else if before.serverNumber == 1, after.serverNumber == 2 {
                events.append(.secondServer)
            }
        }
        if after.endChanges > before.endChanges { events.append(.changeEnds) }

        let isTiebreak: (ScoreDisplay.Phase) -> Bool = { $0 == .tiebreak || $0 == .superTiebreak }
        if isTiebreak(after.phase) && !isTiebreak(before.phase) {
            events.append(.tiebreakStarted)
        }
        return events
    }
}
