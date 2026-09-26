//
//  TournmentStatsEngine.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/26/26.
//
//  TournamentStatsEngine.swift
//  PickleBall
//

import Foundation

enum TournamentStatsEngine {

    // MARK: - Win %

    static func winPercentage(wins: Int, losses: Int, draws: Int = 0) -> Double {
        let total = wins + losses + draws
        guard total > 0 else { return 0 }
        return (Double(wins) / Double(total)) * 100
    }

    static func winPercentageText(wins: Int, losses: Int, draws: Int = 0) -> String {
        let total = wins + losses + draws
        guard total > 0 else { return "—" }
        return "\(Int(winPercentage(wins: wins, losses: losses, draws: draws).rounded()))%"
    }

    // MARK: - Form (last N results, oldest → newest)

    /// `true` = win, `false` = loss. Draws omitted from form chips.
    static func form(
        player: String,
        matches: [TournamentMatch],
        last n: Int = 3
    ) -> [Bool] {
        var results: [Bool] = []
        for match in matches where match.isCompleted {
            guard let winner = match.winner else { continue }
            if match.player1 == player || match.player2 == player {
                results.append(winner == player)
            }
        }
        return Array(results.suffix(n))
    }

    // MARK: - Head-to-head (current tournament only)

    struct H2H: Identifiable, Equatable {
        var id: String { "\(playerA)|\(playerB)" }
        let playerA: String
        let playerB: String
        let aWins: Int
        let bWins: Int

        var summary: String {
            if aWins == bWins { return "\(playerA) tied \(playerB) \(aWins)-\(bWins)" }
            if aWins > bWins { return "\(playerA) leads \(aWins)-\(bWins)" }
            return "\(playerB) leads \(bWins)-\(aWins)"
        }
    }

    static func headToHead(matches: [TournamentMatch]) -> [H2H] {
        var map: [String: (a: String, b: String, aWins: Int, bWins: Int)] = [:]

        for match in matches where match.isCompleted {
            guard let winner = match.winner else { continue }
            let p1 = match.player1
            let p2 = match.player2
            let key = [p1, p2].sorted().joined(separator: "|")
            let ordered = [p1, p2].sorted()
            var entry = map[key] ?? (ordered[0], ordered[1], 0, 0)
            if winner == entry.a {
                entry.aWins += 1
            } else if winner == entry.b {
                entry.bWins += 1
            }
            map[key] = entry
        }

        return map.values
            .map { H2H(playerA: $0.a, playerB: $0.b, aWins: $0.aWins, bWins: $0.bWins) }
            .sorted { $0.playerA < $1.playerA }
    }

    // MARK: - Clutch (deciding-game win rate)

    /// Deciding game = the game that pushed someone to `gamesToWin`.
    /// Returns 0...100, or nil if player has no deciding games.
    static func clutchWinRate(
        player: String,
        matches: [TournamentMatch],
        gamesToWin: Int
    ) -> Double? {
        guard gamesToWin >= 2 else { return nil }

        var decided = 0
        var won = 0

        for match in matches {
            guard match.isCompleted,
                  let scores = match.gameScores, !scores.isEmpty,
                  match.player1 == player || match.player2 == player
            else { continue }

            var p1 = 0
            var p2 = 0
            for (i, game) in scores.enumerated() {
                if game.player1 > game.player2 { p1 += 1 } else if game.player2 > game.player1 { p2 += 1 }
                let isLast = i == scores.count - 1
                let someoneReached = p1 >= gamesToWin || p2 >= gamesToWin
                if isLast && someoneReached {
                    decided += 1
                    let playerWonGame = (match.player1 == player && game.player1 > game.player2)
                        || (match.player2 == player && game.player2 > game.player1)
                    if playerWonGame { won += 1 }
                }
            }
        }

        guard decided > 0 else { return nil }
        return (Double(won) / Double(decided)) * 100
    }

    static func clutchText(player: String, matches: [TournamentMatch], gamesToWin: Int) -> String {
        guard let rate = clutchWinRate(player: player, matches: matches, gamesToWin: gamesToWin) else {
            return "—"
        }
        return "\(Int(rate.rounded()))%"
    }
}
