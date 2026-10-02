//
//  MatchInsights.swift
//  CourtKit
//
//  Match stats straight from the rally log, no Apple Watch needed. The
//  engine knows who served every rally and what was at stake, so serve and
//  return points, runs, comebacks and clutch points are exact in both
//  sports, singles or doubles.
//

import Foundation

public struct MatchInsights: Hashable, Sendable {
    public struct Side: Hashable, Sendable {
        public var ralliesWon = 0
        /// Rallies this side served, and won.
        public var servePlayed = 0
        public var serveWon = 0
        /// Rallies the other side served, and this side won.
        public var returnPlayed = 0
        public var returnWon = 0
        /// Most rallies won in a row.
        public var longestRun = 0
        /// Pickleball side-out scoring: serves won back. Padel: service
        /// games broken.
        public var breaks = 0
        /// Padel: service games played and held.
        public var serviceGames = 0
        public var serviceGamesHeld = 0
        /// Game, set or match points this side had, and how many it took.
        public var pressureChances = 0
        public var pressureConverted = 0
        /// Game, set or match points against this side that it won anyway.
        public var pressureFaced = 0
        public var pressureSaved = 0
        /// Biggest deficit, in points, this side came back from to win a
        /// game (pickleball) or in games to win a set (padel).
        public var biggestComeback = 0

        public init() {}

        public var servePercent: Int? { Self.percent(serveWon, of: servePlayed) }
        public var returnPercent: Int? { Self.percent(returnWon, of: returnPlayed) }
        public var holdPercent: Int? { Self.percent(serviceGamesHeld, of: serviceGames) }

        static func percent(_ part: Int, of whole: Int) -> Int? {
            guard whole > 0 else { return nil }
            return Int((Double(part) / Double(whole) * 100).rounded())
        }
    }

    public var sport: Sport
    public var teams: TeamPair<Side>
    /// Serve record for each player (doubles shows both).
    public var players: [PlayerSlot: ServeStats]
    /// Times the lead in rallies won changed hands.
    public var leadChanges: Int
    /// First to last rally. Nil for scores typed in afterwards.
    public var duration: TimeInterval?
    /// Average time from one rally to the next.
    public var secondsPerRally: Double?
    public var totalRallies: Int

    /// Nothing to show for a score typed in afterwards.
    public var isEmpty: Bool { totalRallies == 0 }

    public static func compute(scorer: MatchScorer) -> MatchInsights {
        let rules = scorer.rules
        let sport = rules.sport
        var teams = TeamPair(repeating: Side())
        var players: [PlayerSlot: ServeStats] = [:]
        var leadChanges = 0
        var leader: Team?
        var runTeam: Team?
        var run = 0

        // Comebacks: worst deficit per side in the current game (pickleball)
        // or set (padel).
        var worst = TeamPair(repeating: 0)
        var unitStartGames = TeamPair(repeating: 0)

        var state = rules.start()
        for rally in scorer.rallies {
            let before = state.display
            let winner = rally.winner

            // What was at stake, before the rally.
            for team in Team.allCases where hasPressure(state, team: team) {
                teams[team].pressureChances += 1
                teams[team.opponent].pressureFaced += 1
                if winner == team { teams[team].pressureConverted += 1 } else { teams[team.opponent].pressureSaved += 1 }
            }

            state = state.rallyWon(by: winner)
            let after = state.display

            teams[winner].ralliesWon += 1
            if runTeam == winner { run += 1 } else { runTeam = winner; run = 1 }
            teams[winner].longestRun = max(teams[winner].longestRun, run)

            let won = TeamPair(a: teams.a.ralliesWon, b: teams.b.ralliesWon)
            let nowLeading: Team? = won.a == won.b ? nil : (won.a > won.b ? .a : .b)
            if let nowLeading, let leader, nowLeading != leader { leadChanges += 1 }
            if let nowLeading { leader = nowLeading }

            if let serving = before.servingTeam {
                teams[serving].servePlayed += 1
                teams[serving.opponent].returnPlayed += 1
                if winner == serving { teams[serving].serveWon += 1 } else { teams[serving.opponent].returnWon += 1 }

                if let server = before.server {
                    var stats = players[server] ?? ServeStats()
                    stats.pointsServed += 1
                    if winner == serving { stats.pointsWonOnServe += 1 }
                    players[server] = stats
                }

                let isTiebreak = before.phase == .tiebreak || before.phase == .superTiebreak
                let gameEnded = after.totalGames != before.totalGames
                if sport == .padel {
                    if !isTiebreak, gameEnded {
                        teams[serving].serviceGames += 1
                        if winner == serving {
                            teams[serving].serviceGamesHeld += 1
                        } else {
                            teams[winner].breaks += 1
                        }
                        if let server = before.server {
                            var stats = players[server] ?? ServeStats()
                            stats.serviceGames += 1
                            if winner == serving { stats.serviceGamesHeld += 1 }
                            players[server] = stats
                        }
                    }
                } else if winner != serving, !gameEnded, after.servingTeam == winner {
                    // Side-out scoring: winning a return wins the serve back.
                    teams[winner].breaks += 1
                }
            }

            // Comebacks.
            if sport == .padel {
                let games = TeamPair(a: after.totalGames.a - unitStartGames.a, b: after.totalGames.b - unitStartGames.b)
                for team in Team.allCases {
                    worst[team] = max(worst[team], games[team.opponent] - games[team])
                }
                if after.sets != before.sets {
                    let setWinner = after.sets.a > before.sets.a ? Team.a : .b
                    teams[setWinner].biggestComeback = max(teams[setWinner].biggestComeback, worst[setWinner])
                    worst = TeamPair(repeating: 0)
                    unitStartGames = after.totalGames
                }
            } else {
                if after.totalGames != before.totalGames {
                    let gameWinner = after.totalGames.a > before.totalGames.a ? Team.a : .b
                    teams[gameWinner].biggestComeback = max(teams[gameWinner].biggestComeback, worst[gameWinner])
                    worst = TeamPair(repeating: 0)
                } else {
                    for team in Team.allCases {
                        worst[team] = max(worst[team], pointsBehind(after, team: team))
                    }
                }
            }
        }

        let times = scorer.rallies.map(\.at)
        var duration: TimeInterval?
        var perRally: Double?
        if let first = times.first, let last = times.last, times.count >= 2, last.timeIntervalSince(first) >= 1 {
            duration = last.timeIntervalSince(first)
            perRally = duration! / Double(times.count - 1)
        }

        return MatchInsights(sport: sport, teams: teams, players: players, leadChanges: leadChanges,
                             duration: duration, secondsPerRally: perRally, totalRallies: scorer.rallies.count)
    }

    /// True when `team` wins a game (or more) by winning the next rally.
    private static func hasPressure(_ state: ScoreState, team: Team) -> Bool {
        guard state.display.winner == nil else { return false }
        let before = state.display
        let after = state.rallyWon(by: team).display
        return after.totalGames[team] > before.totalGames[team] || after.winner == team
    }

    /// Pickleball: how far `team` trails in the current game, read from
    /// the score shown (side-out rallies that score nothing don't count).
    private static func pointsBehind(_ display: ScoreDisplay, team: Team) -> Int {
        guard let mine = Int(display.points[team]), let theirs = Int(display.points[team.opponent]) else { return 0 }
        return max(0, theirs - mine)
    }
}
