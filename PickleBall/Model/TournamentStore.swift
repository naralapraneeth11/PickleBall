//
//  TournamentStore.swift
//  PickleBall
//
//  Tournaments persisted in SwiftData. Screens keep working with the
//  `SavedTournament` value type; the store maps it to and from records.
//

import Foundation
import Combine
import SwiftData
import CourtKit

/// A tournament side: its label as shown in standings plus the players
/// behind it, so every fixture can be scored with real player IDs.
struct TournamentParticipant: Codable, Hashable {
    var label: String
    var players: [PlayerRef]
}

struct SavedTournament: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    var sport: Sport
    var participantNames: [String]
    var participants: [TournamentParticipant]
    var matches: [SavedMatch]
    var shuffledOrder: [UUID]
    var bestOf: Int
    var targetScore: Int
    var isSingles: Bool
    var participantCount: Int
    var name: String?

    var isComplete: Bool { !matches.isEmpty && matches.allSatisfy { $0.isCompleted } }
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

    /// Players behind a label, falling back to a guest per name.
    func players(for label: String) -> [PlayerRef] {
        participants.first { $0.label == label }?.players ?? []
    }

    struct SavedMatch: Identifiable, Codable, Hashable {
        let id: UUID
        var player1: String
        var player2: String
        var player1GamesWon: Int?
        var player2GamesWon: Int?
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

@MainActor
final class TournamentStore: ObservableObject {
    static let shared = TournamentStore()

    @Published private(set) var tournaments: [SavedTournament] = []

    /// Unfinished tournaments, newest first.
    var incompleteTournaments: [SavedTournament] {
        tournaments.filter { !$0.isComplete }.sorted { $0.createdAt > $1.createdAt }
    }

    private var context: ModelContext { AppDatabase.context }

    private init() {
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<TournamentRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        tournaments = ((try? context.fetch(descriptor)) ?? []).map(Self.value(from:))
    }

    func save(_ tournament: SavedTournament) {
        if let record = record(id: tournament.id) {
            Self.update(record, from: tournament, in: context)
        } else {
            Self.insertRecord(for: tournament, into: context)
        }
        AppDatabase.save()
        reload()
    }

    func delete(id: UUID) {
        if let record = record(id: id) {
            context.delete(record)
            AppDatabase.save()
        }
        reload()
    }

    /// Links a finished fixture to the match record that scored it.
    func link(fixture fixtureID: UUID, toMatch matchID: UUID) {
        let raw = fixtureID
        var descriptor = FetchDescriptor<TournamentFixtureRecord>(predicate: #Predicate { $0.id == raw })
        descriptor.fetchLimit = 1
        guard let fixture = try? context.fetch(descriptor).first else { return }
        fixture.matchRecordID = matchID
        AppDatabase.save()
    }

    // MARK: Mapping

    private func record(id: UUID) -> TournamentRecord? {
        let raw = id
        var descriptor = FetchDescriptor<TournamentRecord>(predicate: #Predicate { $0.id == raw })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func insertRecord(for tournament: SavedTournament, into context: ModelContext) {
        let record = TournamentRecord(id: tournament.id, createdAt: tournament.createdAt, sport: tournament.sport)
        context.insert(record)
        update(record, from: tournament, in: context)
    }

    private static func update(_ record: TournamentRecord, from tournament: SavedTournament, in context: ModelContext) {
        record.name = tournament.name
        record.sportRaw = tournament.sport.rawValue
        record.isSingles = tournament.isSingles
        record.bestOf = tournament.bestOf
        record.targetScore = tournament.targetScore
        record.participantCount = tournament.participantCount
        record.shuffledOrder = tournament.shuffledOrder
        record.participantsData = (try? JSONEncoder().encode(tournament.participants)) ?? Data()

        var fixtures = Dictionary(record.fixtures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (order, match) in tournament.matches.enumerated() {
            let fixture: TournamentFixtureRecord
            if let existing = fixtures.removeValue(forKey: match.id) {
                fixture = existing
            } else {
                fixture = TournamentFixtureRecord(id: match.id, order: order, player1: match.player1, player2: match.player2)
                record.fixtures.append(fixture)   // also sets fixture.tournament
            }
            fixture.order = order
            fixture.player1 = match.player1
            fixture.player2 = match.player2
            fixture.player1GamesWon = match.player1GamesWon
            fixture.player2GamesWon = match.player2GamesWon
            fixture.gameScoresData = match.gameScores.flatMap { try? JSONEncoder().encode($0) }
        }
        for orphan in fixtures.values {
            record.fixtures.removeAll { $0.id == orphan.id }
            context.delete(orphan)
        }
    }

    private static func value(from record: TournamentRecord) -> SavedTournament {
        let fixtures = record.fixtures.sorted { $0.order < $1.order }
        let participants = (try? JSONDecoder().decode([TournamentParticipant].self, from: record.participantsData)) ?? []
        var labels: [String] = participants.map(\.label)
        if labels.isEmpty {
            var seen = Set<String>()
            for fixture in fixtures {
                if seen.insert(fixture.player1).inserted { labels.append(fixture.player1) }
                if seen.insert(fixture.player2).inserted { labels.append(fixture.player2) }
            }
        }
        return SavedTournament(
            id: record.id,
            createdAt: record.createdAt,
            sport: Sport(rawValue: record.sportRaw) ?? .pickleball,
            participantNames: labels,
            participants: participants,
            matches: fixtures.map { fixture in
                SavedTournament.SavedMatch(
                    id: fixture.id,
                    player1: fixture.player1,
                    player2: fixture.player2,
                    player1GamesWon: fixture.player1GamesWon,
                    player2GamesWon: fixture.player2GamesWon,
                    gameScores: fixture.gameScoresData.flatMap { try? JSONDecoder().decode([GameScore].self, from: $0) }
                )
            },
            shuffledOrder: record.shuffledOrder,
            bestOf: record.bestOf,
            targetScore: record.targetScore,
            isSingles: record.isSingles,
            participantCount: record.participantCount,
            name: record.name
        )
    }
}
