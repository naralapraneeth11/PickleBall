//
//  LegacyImporter.swift
//  PickleBall
//
//  One-time import of the UserDefaults JSON blobs (career matches, saved
//  tournaments, Watch session history) into SwiftData. The old blobs are
//  left untouched so nothing is lost if the import ever needs to run again.
//
//  Legacy records only know names. Names are matched to players once,
//  here, at import time; from then on everything is keyed by ID.
//

import Foundation
import SwiftData
import CourtKit

@MainActor
enum LegacyImporter {
    static let completedKey = "swiftdata.legacyImport.v1"

    private enum Keys {
        static let matches = "pickleball_stored_matches"
        static let tournaments = "pickleball_saved_tournaments"
        static let watchHistory = "gameHistory"
    }

    static var needsImport: Bool { !UserDefaults.standard.bool(forKey: completedKey) }

    /// Runs the import if it hasn't run yet. Safe to call on every launch.
    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey) else { return }
        let context = AppDatabase.context
        let directory = PlayerDirectory.shared
        var guestsByName: [String: PlayerRef] = [:]

        func guest(_ rawName: String) -> PlayerRef {
            let name = rawName.trimmingCharacters(in: .whitespaces)
            let key = name.lowercased()
            if let existing = guestsByName[key] { return existing }
            let ref = directory.resolve(typedName: name.isEmpty ? "Opponent" : name.capitalized)
            guestsByName[key] = ref
            return ref
        }

        let matches = decode([LegacyStoredMatch].self, key: Keys.matches, defaults: defaults) ?? []
        for legacy in matches {
            importMatch(legacy, me: directory.me, guest: guest, into: context)
        }

        let tournaments = decode([LegacySavedTournament].self, key: Keys.tournaments, defaults: defaults) ?? []
        for legacy in tournaments {
            importTournament(legacy, guest: guest, into: context)
        }

        let sessions = decode([LegacyGameSession].self, key: Keys.watchHistory, defaults: defaults) ?? []
        for legacy in sessions {
            importSession(legacy, into: context)
        }

        AppDatabase.save()
        defaults.set(true, forKey: completedKey)
        directory.reload()
        print("LegacyImporter: imported \(matches.count) matches, \(tournaments.count) tournaments, \(sessions.count) Watch sessions")
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("LegacyImporter: could not decode \(key): \(error)")
            return nil
        }
    }

    // MARK: Matches

    private static func importMatch(
        _ legacy: LegacyStoredMatch,
        me: PlayerRef,
        guest: (String) -> PlayerRef,
        into context: ModelContext
    ) {
        let id = legacy.matchID ?? legacy.id
        let raw = id
        var existing = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.id == raw })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }

        let opponents = legacy.opponent
            .split(separator: "/")
            .map { guest(String($0)) }
        let lineup = Lineup(teamA: [me], teamB: opponents.isEmpty ? [guest("Opponent")] : opponents)
        let games = max(1, max(legacy.myScore, legacy.opponentScore))
        let rules = MatchRules.pickleball(.sideOut, PickleballConfig(gamesToWin: games, isDoubles: lineup.teams.b.count > 1))
        let setup = MatchSetup(matchID: id, rules: rules, lineup: lineup, startedAt: legacy.date, host: .phone)

        let record = MatchRecord(setup: setup, status: .completed)
        record.isLegacyImport = true
        record.endedAt = legacy.date
        record.winnerRaw = (legacy.didWin ? Team.a : Team.b).rawValue
        record.matchScoreA = legacy.myScore
        record.matchScoreB = legacy.opponentScore
        let units = (legacy.gameScores ?? []).map {
            CompletedUnit(score: TeamPair(a: $0.myPoints, b: $0.opponentPoints))
        }
        record.unitsData = try? JSONEncoder().encode(units)
        record.pointsA = units.reduce(0) { $0 + $1.score.a }
        record.pointsB = units.reduce(0) { $0 + $1.score.b }
        record.legacyServePointsPlayed = legacy.servePointsPlayed
        record.legacyServePointsWon = legacy.servePointsWon
        context.insert(record)
    }

    // MARK: Tournaments

    private static func importTournament(
        _ legacy: LegacySavedTournament,
        guest: (String) -> PlayerRef,
        into context: ModelContext
    ) {
        let raw = legacy.id
        var existing = FetchDescriptor<TournamentRecord>(predicate: #Predicate { $0.id == raw })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }

        let labels = legacy.participantNames
        let participants = labels.map { label in
            TournamentParticipant(label: label, players: label.split(separator: "/").map { guest(String($0)) })
        }
        let saved = SavedTournament(
            id: legacy.id,
            createdAt: legacy.createdAt,
            sport: .pickleball,
            participantNames: labels,
            participants: participants,
            matches: legacy.matches.map {
                SavedTournament.SavedMatch(
                    id: $0.id,
                    player1: $0.player1,
                    player2: $0.player2,
                    player1GamesWon: $0.player1GamesWon,
                    player2GamesWon: $0.player2GamesWon,
                    gameScores: $0.gameScores
                )
            },
            shuffledOrder: legacy.shuffledOrder,
            bestOf: legacy.bestOf,
            targetScore: legacy.targetScore,
            isSingles: legacy.isSingles,
            participantCount: legacy.participantCount,
            name: legacy.name
        )
        TournamentStore.insertRecord(for: saved, into: context)
    }

    // MARK: Watch sessions

    private static func importSession(_ legacy: LegacyGameSession, into context: ModelContext) {
        let summary = WorkoutSummary(
            duration: legacy.duration,
            averageHeartRate: legacy.avgHeartRate,
            peakHeartRate: legacy.avgHeartRate,
            calories: legacy.caloriesBurned,
            secondsInZone: [],
            maxHeartRate: nil,
            shots: legacy.totalShots > 0
                ? WorkoutSummary.ShotCounts(
                    forehand: legacy.forehandCount,
                    backhand: legacy.backhandCount,
                    volley: legacy.volleyCount,
                    serve: legacy.serveCount,
                    longestRally: legacy.maxRallyLength
                )
                : nil
        )
        let record = WorkoutSessionRecord(id: legacy.id ?? UUID(), matchID: legacy.matchID, date: legacy.date, summary: summary)
        record.legacyFatigueOnset = legacy.fatigueOnset
        context.insert(record)

        if let matchID = legacy.matchID {
            let raw = matchID
            var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.id == raw })
            descriptor.fetchLimit = 1
            if let match = try? context.fetch(descriptor).first, match.workoutData == nil {
                match.workout = summary
            }
        }
    }
}

// MARK: - Legacy shapes (decoding only)

private struct LegacyGameScore: Codable {
    let myPoints: Int
    let opponentPoints: Int
}

private struct LegacyStoredMatch: Decodable {
    let id: UUID
    let matchID: UUID?
    let opponent: String
    let didWin: Bool
    let myScore: Int
    let opponentScore: Int
    let date: Date
    let gameScores: [LegacyGameScore]?
    let servePointsPlayed: Int?
    let servePointsWon: Int?
}

private struct LegacySavedTournament: Decodable {
    struct Match: Decodable {
        let id: UUID
        let player1: String
        let player2: String
        let player1GamesWon: Int?
        let player2GamesWon: Int?
        let gameScores: [GameScore]?
    }

    let id: UUID
    let createdAt: Date
    let participantNames: [String]
    let matches: [Match]
    let shuffledOrder: [UUID]
    let bestOf: Int
    let targetScore: Int
    let isSingles: Bool
    let participantCount: Int
    let name: String?
}

private struct LegacyGameSession: Decodable {
    let id: UUID?
    let matchID: UUID?
    let date: Date
    let duration: TimeInterval
    let totalShots: Int
    let forehandCount: Int
    let backhandCount: Int
    let volleyCount: Int
    let serveCount: Int
    let maxRallyLength: Int
    let avgHeartRate: Double
    let caloriesBurned: Double
    let fatigueOnset: Double
}
