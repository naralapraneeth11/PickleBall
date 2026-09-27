//
//  ScoreEntry.swift
//  CourtKit
//
//  "Enter a score" after the match: the player types game (or set) scores
//  and this checks them against the format before anything is saved, so a
//  typo like 11-10 or a fourth game in a best of three never reaches an
//  opponent's confirmation screen.
//

import Foundation

public enum ScoreEntryProblem: Error, Hashable, Sendable {
    case noScores
    /// The unit at this index isn't a finished game/set under the rules.
    case invalidUnit(index: Int)
    /// Scores keep going after someone already won the match.
    case extraUnits(from: Int)
    /// Nobody has won enough units yet.
    case undecided
    /// Only the deciding set can be a super tiebreak.
    case misplacedSuperTiebreak(index: Int)

    public func message(for sport: Sport) -> String {
        let unit = sport == .padel ? "Set" : "Game"
        switch self {
        case .noScores: return "Add at least one \(unit.lowercased())."
        case .invalidUnit(let index): return "\(unit) \(index + 1) isn’t a finished score."
        case .extraUnits(let index): return "The match was already over before \(unit.lowercased()) \(index + 1)."
        case .undecided: return "Nobody has won the match yet."
        case .misplacedSuperTiebreak(let index): return "Set \(index + 1) can’t be a match tiebreak."
        }
    }
}

public struct EnteredScore: Hashable, Sendable {
    public let units: [CompletedUnit]
    public let winner: Team
    public let matchScore: TeamPair<Int>
    /// Points (pickleball) or games (padel) won, for the form line.
    public let pointsWon: TeamPair<Int>

    public init(units: [CompletedUnit], winner: Team, matchScore: TeamPair<Int>, pointsWon: TeamPair<Int>) {
        self.units = units
        self.winner = winner
        self.matchScore = matchScore
        self.pointsWon = pointsWon
    }
}

public enum ScoreEntry {
    /// Validates typed units. For padel, a unit with `isSuperTiebreak` holds
    /// its points in `tiebreak`, and a 7-6 set may carry tiebreak points.
    public static func validate(_ units: [CompletedUnit], rules: MatchRules) -> Result<EnteredScore, ScoreEntryProblem> {
        guard !units.isEmpty else { return .failure(.noScores) }

        let needed: Int
        switch rules {
        case .pickleball(_, let config): needed = config.gamesToWin
        case .padel(let config): needed = config.setsToWin
        }

        var won = TeamPair<Int>.zero
        for (index, unit) in units.enumerated() {
            if won.a == needed || won.b == needed { return .failure(.extraUnits(from: index)) }
            let isDecider = won.a == needed - 1 && won.b == needed - 1

            let winner: Team?
            switch rules {
            case .pickleball(_, let config):
                winner = unit.isSuperTiebreak || unit.tiebreak != nil ? nil : pickleballWinner(unit.score, config)
            case .padel(let config):
                if unit.isSuperTiebreak {
                    guard isDecider, case .superTiebreak(let points) = config.decidingSet else {
                        return .failure(.misplacedSuperTiebreak(index: index))
                    }
                    winner = unit.tiebreak.flatMap { tiebreakWinner($0, to: points) }
                } else {
                    if isDecider, case .superTiebreak = config.decidingSet {
                        return .failure(.invalidUnit(index: index))
                    }
                    winner = padelSetWinner(unit, config)
                }
            }
            guard let winner else { return .failure(.invalidUnit(index: index)) }
            won[winner] += 1
        }

        let winner: Team
        if won.a == needed { winner = .a } else if won.b == needed { winner = .b } else { return .failure(.undecided) }

        let points = units.reduce(into: TeamPair<Int>.zero) { total, unit in
            if unit.isSuperTiebreak, let tb = unit.tiebreak {
                total.a += tb.a
                total.b += tb.b
            } else {
                total.a += unit.score.a
                total.b += unit.score.b
            }
        }
        return .success(EnteredScore(units: units, winner: winner, matchScore: won, pointsWon: points))
    }

    /// A finished pickleball game: first to the target, win by the margin,
    /// never past the point where the game would already have ended.
    static func pickleballWinner(_ score: TeamPair<Int>, _ config: PickleballConfig) -> Team? {
        guard let leader = score.leader else { return nil }
        let w = score[leader], l = score[leader.opponent]
        guard l >= 0 else { return nil }
        if let cap = config.pointCap {
            if w > cap { return nil }
            if w == cap, l < cap { return leader }
        }
        guard config.hasWonGame(w, against: l) else { return nil }
        // Exactly the point that ended it: the target, or the margin once
        // both were past it.
        if l <= config.pointsToWin - config.winBy {
            return w == config.pointsToWin ? leader : nil
        }
        return w - l == config.winBy ? leader : nil
    }

    /// 6-x (x ≤ 4), 7-5, or 7-6 with an optional tiebreak score.
    static func padelSetWinner(_ unit: CompletedUnit, _ config: PadelConfig) -> Team? {
        let n = config.gamesPerSet
        guard let leader = unit.score.leader else { return nil }
        let w = unit.score[leader], l = unit.score[leader.opponent]
        if w == n && l <= n - 2 { return unit.tiebreak == nil ? leader : nil }
        if w == n + 1 && l == n - 1 { return unit.tiebreak == nil ? leader : nil }
        if w == n + 1 && l == n {
            guard let tb = unit.tiebreak else { return leader }
            return tiebreakWinner(tb, to: config.tiebreakPoints) == leader ? leader : nil
        }
        return nil
    }

    /// First to `points`, win by two, ending on the deciding point.
    static func tiebreakWinner(_ score: TeamPair<Int>, to points: Int) -> Team? {
        guard let leader = score.leader else { return nil }
        let w = score[leader], l = score[leader.opponent]
        if l <= points - 2 { return w == points ? leader : nil }
        return w - l == 2 ? leader : nil
    }
}
