import Foundation
import Combine
import SwiftUI
// MARK: - Saved Tournament Models
struct SavedTournament: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var participantNames: [String]
    var matches: [SavedMatch]
    var shuffledOrder: [UUID]
    var bestOf: Int
    var targetScore: Int
    var isSingles: Bool
    var participantCount: Int
    var name: String?
    var isComplete: Bool { matches.allSatisfy { $0.isCompleted } }
    var completedCount: Int { matches.filter { $0.isCompleted }.count }
    var displayTitle: String {
        let names = participantNames.filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Tournament" }
        if names.count <= 3 { return names.joined(separator: " · ") }
        return "\(names.prefix(3).joined(separator: " · ")) +\(names.count - 3)"
    }
    var resolvedTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name.trimmingCharacters(in: .whitespaces)
        }
        return displayTitle
    }
    struct SavedMatch: Identifiable, Codable {
        let id: UUID
        var player1: String
        var player2: String
        var player1GamesWon: Int?
        var player2GamesWon: Int?
        /// Per-game scores for restoring rally-level history on resume.
        /// GameScore lives in GameScene.swift and is Codable.
        var gameScores: [GameScore]?

        var isCompleted: Bool { player1GamesWon != nil && player2GamesWon != nil }
        var winner: String? {
            guard let p1 = player1GamesWon, let p2 = player2GamesWon else { return nil }
            return p1 > p2 ? player1 : player2
        }
        var scoreText: String? {
            guard let p1 = player1GamesWon, let p2 = player2GamesWon else { return nil }
            return "\(p1)-\(p2)"
        }
    }
}
// MARK: - Tournament Store
@MainActor
final class TournamentStore: ObservableObject {
    static let shared = TournamentStore()

    private let key = "pickleball_saved_tournaments"

    @Published private(set) var tournaments: [SavedTournament] = []

    /// Tournaments that are NOT complete, sorted by createdAt descending
    /// (most recent first) so the "Continue Tournament" list in PlayView
    /// has a stable order regardless of save sequence.
    var incompleteTournaments: [SavedTournament] {
        tournaments
            .filter { !$0.isComplete }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private init() {
        load()
    }
    func save(_ tournament: SavedTournament) {
        if let idx = tournaments.firstIndex(where: { $0.id == tournament.id }) {
            tournaments[idx] = tournament
        } else {
            tournaments.append(tournament)
        }
        persist()
    }
    func delete(id: UUID) {
        tournaments.removeAll { $0.id == id }
        persist()
    }
    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            tournaments = []
            return
        }
        do {
            tournaments = try JSONDecoder().decode([SavedTournament].self, from: data)
        } catch {
            // Schema drift: preserve the bad blob so we can recover later
            // and start fresh rather than silently overwriting user data.
            // Same pattern as WatchConnectivityManager.loadHistory().
            let backupKey = "\(key)_corrupt_\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backupKey)
            UserDefaults.standard.removeObject(forKey: key)
            tournaments = []
            print("TournamentStore: failed to decode saved tournaments, backed up to \(backupKey). Error: \(error.localizedDescription)")
        }
    }
    private func persist() {
        do {
            let data = try JSONEncoder().encode(tournaments)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("TournamentStore: failed to encode tournaments. Error: \(error.localizedDescription)")
        }
    }
}
