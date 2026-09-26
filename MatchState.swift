//  MatchState.swift
//  PickleBall
//
//  Shared phone ↔ watch live match payload.
//  Single source of truth — do not duplicate in GameScene or Watch targets.
//

import Foundation

struct MatchState: Equatable {
    static let messageType = "phoneMatchState"

    var matchID: UUID
    var timestamp: TimeInterval
    var isMatchActive: Bool
    var player1Name: String
    var player2Name: String
    var player1Points: Int
    var player2Points: Int
    var player1GamesWon: Int
    var player2GamesWon: Int
    var isPlayer1Serving: Bool
    var totalGames: Int
    var targetScore: Int
    var matchCompleted: Bool
    var wonByPlayer1: Bool
    var completedGameScores: [GameScore]
    
    // PRO: Serve hold stats
    var servePointsPlayed: Int = 0
    var servePointsWon: Int = 0
    
    init(
        matchID: UUID = UUID(),
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        isMatchActive: Bool,
        player1Name: String,
        player2Name: String,
        player1Points: Int,
        player2Points: Int,
        player1GamesWon: Int,
        player2GamesWon: Int,
        isPlayer1Serving: Bool,
        totalGames: Int,
        targetScore: Int,
        matchCompleted: Bool,
        wonByPlayer1: Bool,
        completedGameScores: [GameScore],
        // ✅ FIXED: Added to init signature
        servePointsPlayed: Int = 0,
        servePointsWon: Int = 0
    ) {
        self.matchID = matchID
        self.timestamp = timestamp
        self.isMatchActive = isMatchActive
        self.player1Name = player1Name
        self.player2Name = player2Name
        self.player1Points = player1Points
        self.player2Points = player2Points
        self.player1GamesWon = player1GamesWon
        self.player2GamesWon = player2GamesWon
        self.isPlayer1Serving = isPlayer1Serving
        self.totalGames = totalGames
        self.targetScore = targetScore
        self.matchCompleted = matchCompleted
        self.wonByPlayer1 = wonByPlayer1
        self.completedGameScores = completedGameScores
        
        // ✅ FIXED: Assign properties
        self.servePointsPlayed = servePointsPlayed
        self.servePointsWon = servePointsWon
    }

    init?(message: [String: Any]) {
        let type = message["type"] as? String
        guard type == "phoneMatchState" || type == "watchMatchState" || type == "matchState" else {
            return nil
        }

        func intValue(_ value: Any?) -> Int {
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            return 0
        }

        func boolValue(_ value: Any?) -> Bool {
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            return false
        }

        guard let matchIDString = message["matchID"] as? String,
              let matchID = UUID(uuidString: matchIDString) else {
            return nil
        }

        self.matchID = matchID
        self.timestamp = (message["timestamp"] as? Double) ?? Date().timeIntervalSince1970
        self.isMatchActive = boolValue(message["isMatchActive"])
        self.player1Name = (message["player1Name"] as? String) ?? "PLAYER1"
        self.player2Name = (message["player2Name"] as? String) ?? "PLAYER2"
        self.player1Points = intValue(message["player1Points"])
        self.player2Points = intValue(message["player2Points"])
        self.player1GamesWon = intValue(message["player1GamesWon"])
        self.player2GamesWon = intValue(message["player2GamesWon"])
        self.isPlayer1Serving = boolValue(message["isPlayer1Serving"])
        self.totalGames = max(1, intValue(message["totalGames"]))
        self.targetScore = max(1, intValue(message["targetScore"]))
        self.matchCompleted = boolValue(message["matchCompleted"])
        self.wonByPlayer1 = boolValue(message["wonByPlayer1"])
        
        // ✅ FIXED: Parse serve stats from Watch
        self.servePointsPlayed = intValue(message["servePointsPlayed"])
        self.servePointsWon = intValue(message["servePointsWon"])

        if let rawScores = message["completedGameScores"] as? [[Int]] {
            self.completedGameScores = rawScores.map {
                GameScore(player1: $0.first ?? 0, player2: $0.dropFirst().first ?? 0)
            }
        } else {
            self.completedGameScores = []
        }
    }

    var dictionary: [String: Any] {
        [
            "type": Self.messageType,
            "matchID": matchID.uuidString,
            "timestamp": timestamp,
            "isMatchActive": isMatchActive,
            "player1Name": player1Name,
            "player2Name": player2Name,
            "player1Points": player1Points,
            "player2Points": player2Points,
            "player1GamesWon": player1GamesWon,
            "player2GamesWon": player2GamesWon,
            "isPlayer1Serving": isPlayer1Serving,
            "totalGames": totalGames,
            "targetScore": targetScore,
            "matchCompleted": matchCompleted,
            "wonByPlayer1": wonByPlayer1,
            "completedGameScores": completedGameScores.map { [$0.player1, $0.player2] },
            // ✅ FIXED: Send serve stats to Phone
            "servePointsPlayed": servePointsPlayed,
            "servePointsWon": servePointsWon
        ]
    }
}
