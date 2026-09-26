//
//  TournamentModels.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/24/26.
//

import Foundation

// 1. From TournamentSetupView.swift
struct MatchToPlay: Identifiable {
    let id = UUID()
    let index: Int
    let player1: String
    let player2: String
}

// 2. From TournamentSetupView.swift
struct TournamentMatch: Identifiable {
    let id: UUID
    var player1: String
    var player2: String
    var player1GamesWon: Int?
    var player2GamesWon: Int?
    var gameScores: [GameScore]?

    var winner: String? {
        guard let p1 = player1GamesWon, let p2 = player2GamesWon else { return nil }
        return p1 > p2 ? player1 : player2
    }

    var isCompleted: Bool { winner != nil }

    var scoreText: String? {
        guard let p1 = player1GamesWon, let p2 = player2GamesWon else { return nil }
        return "\(p1)-\(p2)"
    }

    var player1TotalPoints: Int { gameScores?.reduce(0) { $0 + $1.player1 } ?? 0 }
    var player2TotalPoints: Int { gameScores?.reduce(0) { $0 + $1.player2 } ?? 0 }
}

// 3. From TournamentSetupView.swift
struct PlayerStanding: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var points: Int
    var wins: Int
    var draws: Int
    var losses: Int
    var pointsFor: Int
    var pointsAgainst: Int
    var pointDifferential: Int { pointsFor - pointsAgainst }
}

// 4. Per-game score for tournament fixtures (team A = player1).
struct GameScore: Codable, Hashable {
    var player1: Int
    var player2: Int
}
