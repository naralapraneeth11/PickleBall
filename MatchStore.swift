//
//  MatchStore.swift
//  PickleBall
//

import Foundation
import Combine
import SwiftUI

// MARK: - Stored Match

struct MatchGameScore: Codable, Equatable {
    let myPoints: Int
    let opponentPoints: Int
}

struct StoredMatch: Identifiable, Codable, Equatable {
    let id: UUID
    /// matchID from GameSceneView. Used to dedupe against incoming
    /// gameComplete payloads from the watch so the same match
    /// doesn't get saved twice from two different code paths.
    let matchID: UUID?
    /// First name of the profile player at the time the match was saved.
    let playerName: String
    let opponent: String
    let didWin: Bool
    let myScore: Int
    let opponentScore: Int
    let date: Date
    let gameScores: [MatchGameScore]?

    // MARK: Serve hold (scoring truth — not Watch serve swings)
    /// Points played while the profile player was serving.
    let servePointsPlayed: Int?
    /// Points the profile player won while serving.
    let servePointsWon: Int?

    /// Hold % for this match, or nil if no serve points were logged.
    var serveHoldPercent: Int? {
        guard let played = servePointsPlayed, played > 0,
              let won = servePointsWon else { return nil }
        return Int((Double(won) / Double(played) * 100).rounded())
    }

    init(
        id: UUID = UUID(),
        matchID: UUID? = nil,
        playerName: String,
        opponent: String,
        didWin: Bool,
        myScore: Int,
        opponentScore: Int,
        date: Date = Date(),
        gameScores: [MatchGameScore]? = nil,
        servePointsPlayed: Int? = nil,
        servePointsWon: Int? = nil
    ) {
        self.id = id
        self.matchID = matchID
        self.playerName = playerName
        self.opponent = opponent
        self.didWin = didWin
        self.myScore = myScore
        self.opponentScore = opponentScore
        self.date = date
        self.gameScores = gameScores
        self.servePointsPlayed = servePointsPlayed
        self.servePointsWon = servePointsWon
    }

    // Custom decoder: legacy matches without playerName / matchID / serve fields
    // decode cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.matchID = try c.decodeIfPresent(UUID.self, forKey: .matchID)
        self.playerName = try c.decodeIfPresent(String.self, forKey: .playerName) ?? ""
        self.opponent = try c.decode(String.self, forKey: .opponent)
        self.didWin = try c.decode(Bool.self, forKey: .didWin)
        self.myScore = try c.decode(Int.self, forKey: .myScore)
        self.opponentScore = try c.decode(Int.self, forKey: .opponentScore)
        self.date = try c.decode(Date.self, forKey: .date)
        self.gameScores = try c.decodeIfPresent([MatchGameScore].self, forKey: .gameScores)
        self.servePointsPlayed = try c.decodeIfPresent(Int.self, forKey: .servePointsPlayed)
        self.servePointsWon = try c.decodeIfPresent(Int.self, forKey: .servePointsWon)
    }
}

// MARK: - Match Store

@MainActor
final class MatchStore: ObservableObject {
    static let shared = MatchStore()

    private let key = "pickleball_stored_matches"

    @Published private(set) var matches: [StoredMatch] = []

    private init() {
        loadMatches()
    }

    // MARK: - Persistence

    private func loadMatches() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            matches = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([StoredMatch].self, from: data)
            matches = decoded.sorted { $0.date > $1.date }
        } catch {
            let backupKey = "\(key)_corrupt_\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backupKey)
            UserDefaults.standard.removeObject(forKey: key)
            matches = []
            print("MatchStore: failed to decode matches, backed up to \(backupKey). Error: \(error.localizedDescription)")
        }
    }

    func addMatch(_ match: StoredMatch) {
        if let mid = match.matchID,
           let existingIdx = matches.firstIndex(where: { $0.matchID == mid }) {
            matches[existingIdx] = match
        } else {
            matches.insert(match, at: 0)
        }
        saveMatches()
    }

    private func saveMatches() {
        do {
            let data = try JSONEncoder().encode(matches)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("MatchStore: failed to encode matches. Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Stats for a specific player

    func matchesForPlayer(firstName: String) -> [StoredMatch] {
        let target = firstName.trimmingCharacters(in: .whitespaces).uppercased()
        guard !target.isEmpty else { return [] }
        return matches.filter { stored in
            stored.playerName.isEmpty
                || stored.playerName.uppercased() == target
        }
    }

    func totalWins(firstName: String) -> Int {
        matchesForPlayer(firstName: firstName).filter { $0.didWin }.count
    }

    func totalMatches(firstName: String) -> Int {
        matchesForPlayer(firstName: firstName).count
    }

    func averagePointsScored(firstName: String) -> Double {
        let playerMatches = matchesForPlayer(firstName: firstName)
        guard !playerMatches.isEmpty else { return 0 }
        var totalPoints = 0
        var totalGames = 0
        for match in playerMatches {
            if let gameScores = match.gameScores, !gameScores.isEmpty {
                totalPoints += gameScores.reduce(0) { $0 + $1.myPoints }
                totalGames += gameScores.count
            }
        }
        guard totalGames > 0 else { return 0 }
        return Double(totalPoints) / Double(totalGames)
    }

    func winPercentage(firstName: String) -> Double {
        let total = totalMatches(firstName: firstName)
        guard total > 0 else { return 0 }
        return (Double(totalWins(firstName: firstName)) / Double(total)) * 100
    }

    func bestWinMargin(firstName: String) -> Int {
        matchesForPlayer(firstName: firstName)
            .filter { $0.didWin }
            .map { $0.myScore - $0.opponentScore }
            .max() ?? 0
    }

    func bestWinScore(firstName: String) -> String {
        let wins = matchesForPlayer(firstName: firstName).filter { $0.didWin }
        guard !wins.isEmpty else { return "—" }

        var bestScore: MatchGameScore?
        var bestDiff = Int.min

        for match in wins {
            if let gameScores = match.gameScores, !gameScores.isEmpty {
                for game in gameScores {
                    let diff = game.myPoints - game.opponentPoints
                    if diff > bestDiff
                        || (diff == bestDiff && game.myPoints > (bestScore?.myPoints ?? 0)) {
                        bestDiff = diff
                        bestScore = game
                    }
                }
            } else {
                let diff = match.myScore - match.opponentScore
                if diff > bestDiff
                    || (diff == bestDiff && match.myScore > (bestScore?.myPoints ?? 0)) {
                    bestDiff = diff
                    bestScore = MatchGameScore(myPoints: match.myScore, opponentPoints: match.opponentScore)
                }
            }
        }
        guard let bestScore else { return "—" }
        return "\(bestScore.myPoints)-\(bestScore.opponentPoints)"
    }

    func recentMatches(firstName: String, limit: Int = 20) -> [StoredMatch] {
        Array(matchesForPlayer(firstName: firstName).prefix(limit))
    }

    // MARK: - Serve hold (aggregate)

    /// Total serve points played / won for this profile player.
    func serveHoldStats(firstName: String) -> (played: Int, won: Int, percent: Int?) {
        let list = matchesForPlayer(firstName: firstName)
        let played = list.reduce(0) { $0 + ($1.servePointsPlayed ?? 0) }
        let won = list.reduce(0) { $0 + ($1.servePointsWon ?? 0) }
        guard played > 0 else { return (0, 0, nil) }
        let pct = Int((Double(won) / Double(played) * 100).rounded())
        return (played, won, pct)
    }
}

// MARK: - Player Match Check

func isProfilePlayerInMatch(profileFirstName: String, player1Display: String, player2Display: String) -> Bool {
    MatchRecorder.isProfilePlayerInMatch(
        profileFirstName: profileFirstName,
        player1Display: player1Display,
        player2Display: player2Display
    )
}

func profilePlayerSide(profileFirstName: String, player1Display: String, player2Display: String) -> Int? {
    MatchRecorder.profilePlayerSide(
        profileFirstName: profileFirstName,
        player1Display: player1Display,
        player2Display: player2Display
    )
}
