//
//  Drama.swift
//  CourtKit
//
//  Finds the story in a match: comebacks, saved match points, runs, lead
//  changes, marathon games, bagels, deciders. Watch-scored matches have a
//  rally log, so the detector replays it point by point. Matches entered
//  later only have game scores, so it reads what those can tell.
//
//  The result drives the Replay, the headline on the score card and the
//  "big comeback" share prompt.
//

import Foundation

public struct DramaReport: Hashable, Codable, Sendable {
    public enum Moment: Hashable, Codable, Sendable {
        /// Won a game/set after trailing by `deficit` points (pickleball) or
        /// games (padel). `trailing` is the score at the low point, from the
        /// comeback team's side.
        case comeback(team: Team, unit: Int, deficit: Int, trailing: TeamPair<Int>)
        /// Won the match after losing the first `units` games/sets.
        case matchComeback(team: Team, units: Int)
        /// Faced match point `count` times and survived.
        case savedMatchPoints(team: Team, count: Int)
        /// Unanswered points (pickleball) or games (padel) in one game/set.
        case run(team: Team, length: Int, unit: Int)
        case leadChanges(count: Int)
        /// A game past the target (13-11 and beyond) or a set to a tiebreak.
        case marathon(unit: Int, score: TeamPair<Int>)
        /// 11-0 or 6-0.
        case bagel(team: Team, unit: Int)
        /// Went the distance: the deciding game or set was played.
        case decider
    }

    public let moments: [Moment]
    /// 0…1: how much of a story this match is.
    public let intensity: Double
    public let winner: Team?

    /// A comeback worth offering a share card for.
    public var isBigComeback: Bool {
        moments.contains { moment in
            switch moment {
            case .comeback(let team, _, let deficit, _):
                return team == winner && deficit >= DramaDetector.bigDeficit(for: sport)
            case .savedMatchPoints(let team, _):
                return team == winner
            case .matchComeback(let team, let units):
                return team == winner && units >= 2
            default:
                return false
            }
        }
    }

    public let sport: Sport

    /// One line for the score card and the Replay title.
    public func headline(_ lineup: Lineup) -> String {
        guard let top = moments.first else {
            guard let winner else { return "Match drawn" }
            return "\(lineup.name(of: winner, separator: " & ")) win"
        }
        return DramaDetector.describe(top, lineup: lineup, sport: sport)
    }

    public func lines(_ lineup: Lineup) -> [String] {
        moments.map { DramaDetector.describe($0, lineup: lineup, sport: sport) }
    }
}

public enum DramaDetector {
    static func bigDeficit(for sport: Sport) -> Int { sport == .padel ? 3 : 5 }
    static func runWorthMentioning(for sport: Sport) -> Int { sport == .padel ? 4 : 6 }
    static func comebackWorthMentioning(for sport: Sport) -> Int { sport == .padel ? 2 : 4 }

    /// Point-by-point analysis of a scored match.
    public static func analyze(rules: MatchRules, rallies: [Rally]) -> DramaReport {
        let sport = rules.sport
        var scorer = MatchScorer(rules: rules)
        var moments: [DramaReport.Moment] = []

        var unitIndex = 0
        var unitScore = TeamPair<Int>.zero
        var worst = TeamPair<Int>.zero            // biggest deficit each team faced this unit
        var worstScore = TeamPair(repeating: TeamPair<Int>.zero)
        var runTeam: Team?
        var runLength = 0
        var bestRun: (team: Team, length: Int, unit: Int)?
        var leader: Team?
        var leadChanges = 0
        var matchPointsSaved = TeamPair<Int>.zero

        for rally in rallies where !scorer.isFinished {
            // Match point faced: the other side would win the match on this rally.
            for team in Team.allCases where scorer.pressure(for: team.opponent) == .matchPoint && rally.winner == team {
                matchPointsSaved[team] += 1
            }

            let before = scorer.display
            scorer.recordRally(wonBy: rally.winner)
            let after = scorer.display
            let unitEnded = after.completed.count > before.completed.count

            let newScore: TeamPair<Int>
            if unitEnded, let unit = after.completed.last {
                newScore = unit.isSuperTiebreak ? (unit.tiebreak ?? .zero) : unit.score
            } else {
                newScore = unitScoreOf(after)
            }

            // Unanswered scoring.
            for team in Team.allCases where newScore[team] > unitScore[team] {
                if runTeam == team { runLength += newScore[team] - unitScore[team] } else {
                    runTeam = team
                    runLength = newScore[team] - unitScore[team]
                }
                if runLength > (bestRun?.length ?? 0) { bestRun = (team, runLength, unitIndex) }
            }

            // Lead changes (ties don't count as a change).
            if let current = newScore.leader {
                if let leader, leader != current { leadChanges += 1 }
                leader = current
            }

            for team in Team.allCases {
                let deficit = newScore[team.opponent] - newScore[team]
                if deficit > worst[team] {
                    worst[team] = deficit
                    worstScore[team] = TeamPair(a: newScore[team], b: newScore[team.opponent])
                }
            }
            unitScore = newScore

            if unitEnded, let unit = after.completed.last, let unitWinner = unit.winner {
                if worst[unitWinner] >= comebackWorthMentioning(for: sport) {
                    moments.append(.comeback(team: unitWinner, unit: unitIndex, deficit: worst[unitWinner], trailing: worstScore[unitWinner]))
                }
                unitIndex += 1
                unitScore = .zero
                worst = .zero
                worstScore = TeamPair(repeating: .zero)
                runTeam = nil
                runLength = 0
                leader = nil
            }
        }

        let winner = scorer.winner
        for team in Team.allCases where matchPointsSaved[team] > 0 {
            moments.append(.savedMatchPoints(team: team, count: matchPointsSaved[team]))
        }
        if let bestRun, bestRun.length >= runWorthMentioning(for: sport) {
            moments.append(.run(team: bestRun.team, length: bestRun.length, unit: bestRun.unit))
        }
        if leadChanges >= 4 { moments.append(.leadChanges(count: leadChanges)) }
        moments += unitMoments(units: scorer.display.completed, rules: rules, winner: winner)

        return report(moments: moments, winner: winner, sport: sport)
    }

    /// What game scores alone can tell (matches entered after the fact).
    public static func analyze(units: [CompletedUnit], rules: MatchRules, winner: Team?) -> DramaReport {
        report(moments: unitMoments(units: units, rules: rules, winner: winner), winner: winner, sport: rules.sport)
    }

    // MARK: - Pieces

    static func unitScoreOf(_ display: ScoreDisplay) -> TeamPair<Int> {
        switch display.sport {
        case .pickleball:
            return display.points.map { Int($0) ?? 0 }
        case .padel:
            if display.phase == .superTiebreak { return display.points.map { Int($0) ?? 0 } }
            return display.games
        }
    }

    static func unitMoments(units: [CompletedUnit], rules: MatchRules, winner: Team?) -> [DramaReport.Moment] {
        var moments: [DramaReport.Moment] = []
        let maxUnits: Int
        let target: Int
        switch rules {
        case .pickleball(_, let config):
            maxUnits = config.maxGames
            target = config.pointsToWin
        case .padel(let config):
            maxUnits = config.setsToWin * 2 - 1
            target = config.gamesPerSet
        }

        if maxUnits > 1, units.count == maxUnits { moments.append(.decider) }

        if let winner {
            let lostFirst = units.prefix { $0.winner == winner.opponent }.count
            if lostFirst > 0 { moments.append(.matchComeback(team: winner, units: lostFirst)) }
        }

        for (index, unit) in units.enumerated() where !unit.isSuperTiebreak {
            let high = max(unit.score.a, unit.score.b)
            switch rules.sport {
            case .pickleball where high >= target + 2:
                moments.append(.marathon(unit: index, score: unit.score))
            case .padel where unit.tiebreak != nil:
                moments.append(.marathon(unit: index, score: unit.score))
            default:
                break
            }
            if let unitWinner = unit.winner, unit.score[unitWinner.opponent] == 0, unit.score[unitWinner] >= min(target, 6) {
                moments.append(.bagel(team: unitWinner, unit: index))
            }
        }
        return moments
    }

    static func weight(_ moment: DramaReport.Moment, sport: Sport, winner: Team?) -> Double {
        switch moment {
        case .savedMatchPoints(let team, let count):
            return (team == winner ? 0.45 : 0.2) + 0.05 * Double(min(count, 3) - 1)
        case .comeback(let team, _, let deficit, _):
            let scale = Double(deficit) / Double(bigDeficit(for: sport))
            return min(0.4, 0.2 * scale) + (team == winner ? 0.05 : 0)
        case .matchComeback(let team, let units):
            return team == winner ? 0.2 + 0.1 * Double(units - 1) : 0
        case .decider: return 0.2
        case .marathon: return 0.12
        case .leadChanges(let count): return min(0.2, 0.03 * Double(count))
        case .run(_, let length, _):
            return min(0.15, 0.02 * Double(length))
        case .bagel: return 0.1
        }
    }

    static func report(moments: [DramaReport.Moment], winner: Team?, sport: Sport) -> DramaReport {
        let ranked = moments.enumerated().sorted { lhs, rhs in
            let l = weight(lhs.element, sport: sport, winner: winner)
            let r = weight(rhs.element, sport: sport, winner: winner)
            return l != r ? l > r : lhs.offset < rhs.offset
        }.map(\.element)
        let total = ranked.reduce(0) { $0 + weight($1, sport: sport, winner: winner) }
        return DramaReport(moments: ranked, intensity: min(1, total), winner: winner, sport: sport)
    }

    static func describe(_ moment: DramaReport.Moment, lineup: Lineup, sport: Sport) -> String {
        let unitName = sport == .padel ? "set" : "game"
        func who(_ team: Team) -> String { lineup.name(of: team, separator: " & ") }
        func ordinal(_ index: Int) -> String {
            ["first", "second", "third", "fourth", "fifth"][safe: index] ?? "\(index + 1)th"
        }
        switch moment {
        case .comeback(let team, let unit, _, let trailing):
            return "\(who(team)) came back from \(trailing.a)-\(trailing.b) down in the \(ordinal(unit)) \(unitName)"
        case .matchComeback(let team, let units):
            let lost = units == 1 ? "the first \(unitName)" : "the first \(units) \(unitName)s"
            return "\(who(team)) lost \(lost) and still won"
        case .savedMatchPoints(let team, let count):
            return "\(who(team)) saved \(count == 1 ? "a match point" : "\(count) match points")"
        case .run(let team, let length, _):
            return "\(who(team)) went on a \(length)-\(sport == .padel ? "game" : "point") run"
        case .leadChanges(let count):
            return "The lead changed hands \(count) times"
        case .marathon(let unit, let score):
            return "A \(max(score.a, score.b))-\(min(score.a, score.b)) marathon in the \(ordinal(unit)) \(unitName)"
        case .bagel(let team, let unit):
            return "\(who(team)) served up a bagel in the \(ordinal(unit)) \(unitName)"
        case .decider:
            return "It went the distance"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
