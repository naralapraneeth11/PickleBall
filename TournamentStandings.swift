//
//  TournamentStandings.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/24/26.
//

import Foundation

enum TournamentStandings {

    /// Pure function: given completed matches, returns ranked standings.
    /// Ranking order: points → point differential → points for.
    static func compute(from matches: [TournamentMatch]) -> [PlayerStanding] {
        var stats: [String: (points: Int, wins: Int, draws: Int, losses: Int, pointsFor: Int, pointsAgainst: Int)] = [:]

        for match in matches {
            guard let p1Games = match.player1GamesWon,
                  let p2Games = match.player2GamesWon else { continue }

            if stats[match.player1] == nil {
                stats[match.player1] = (0, 0, 0, 0, 0, 0)
            }
            if stats[match.player2] == nil {
                stats[match.player2] = (0, 0, 0, 0, 0, 0)
            }

            // Prefer actual point totals from game scores when available;
            // fall back to games-won when history is missing.
            let p1Points = match.gameScores != nil ? match.player1TotalPoints : p1Games
            let p2Points = match.gameScores != nil ? match.player2TotalPoints : p2Games

            stats[match.player1]!.pointsFor += p1Points
            stats[match.player1]!.pointsAgainst += p2Points
            stats[match.player2]!.pointsFor += p2Points
            stats[match.player2]!.pointsAgainst += p1Points

            if p1Games > p2Games {
                stats[match.player1]!.wins += 1
                stats[match.player1]!.points += 2
                stats[match.player2]!.losses += 1
            } else if p2Games > p1Games {
                stats[match.player2]!.wins += 1
                stats[match.player2]!.points += 2
                stats[match.player1]!.losses += 1
            } else {
                stats[match.player1]!.draws += 1
                stats[match.player2]!.draws += 1
                stats[match.player1]!.points += 1
                stats[match.player2]!.points += 1
            }
        }

        return stats.map { name, s in
            PlayerStanding(
                name: name,
                points: s.points,
                wins: s.wins,
                draws: s.draws,
                losses: s.losses,
                pointsFor: s.pointsFor,
                pointsAgainst: s.pointsAgainst
            )
        }
        .sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.pointDifferential != b.pointDifferential {
                return a.pointDifferential > b.pointDifferential
            }
            return a.pointsFor > b.pointsFor
        }
    }
}
