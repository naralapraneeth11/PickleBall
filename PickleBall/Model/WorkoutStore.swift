//
//  WorkoutStore.swift
//  PickleBall
//
//  Watch workout sessions in SwiftData, exposed as `GameSession` rows for
//  the Watch stats screens.
//

import Foundation
import Combine
import SwiftData
import CourtKit

/// Read model for one Watch session.
struct GameSession: Identifiable, Equatable {
    let id: UUID
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
    let peakHeartRate: Double
    let caloriesBurned: Double
    /// Seconds per heart-rate zone; empty for sessions recorded before zones.
    let secondsInZone: [Double]
    /// Share of time at threshold or above (0…1).
    let hardShare: Double
    let dominantZone: HeartRateZones.Zone?

    init(record: WorkoutSessionRecord) {
        let summary = record.summary
        id = record.id
        matchID = record.matchID
        date = record.date
        duration = summary?.duration ?? 0
        forehandCount = summary?.shots?.forehand ?? 0
        backhandCount = summary?.shots?.backhand ?? 0
        volleyCount = summary?.shots?.volley ?? 0
        serveCount = summary?.shots?.serve ?? 0
        totalShots = summary?.shots?.total ?? 0
        maxRallyLength = summary?.shots?.longestRally ?? 0
        avgHeartRate = summary?.averageHeartRate ?? 0
        peakHeartRate = summary?.peakHeartRate ?? 0
        caloriesBurned = summary?.calories ?? 0
        secondsInZone = summary?.secondsInZone ?? []
        hardShare = summary?.hardShare ?? 0
        dominantZone = summary?.dominantZone
    }
}

@MainActor
final class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()

    /// Oldest first.
    @Published private(set) var sessions: [GameSession] = []

    private var context: ModelContext { AppDatabase.context }

    private init() {
        reload()
    }

    var latest: GameSession? { sessions.last }

    func reload() {
        let descriptor = FetchDescriptor<WorkoutSessionRecord>(sortBy: [SortDescriptor(\.date)])
        sessions = ((try? context.fetch(descriptor)) ?? [])
            .filter { AccountScope.owns($0.ownerAccountID) }
            .map(GameSession.init(record:))
    }

    /// Stores a report from the Watch and attaches it to its match.
    func add(_ report: WorkoutReport, matchID: UUID?, date: Date) {
        if let matchID {
            let raw: UUID? = matchID
            var existing = FetchDescriptor<WorkoutSessionRecord>(predicate: #Predicate { $0.matchID == raw })
            existing.fetchLimit = 1
            if let record = try? context.fetch(existing).first {
                record.summary = report
            } else {
                context.insert(WorkoutSessionRecord(matchID: matchID, date: date, summary: report))
            }
            MatchStore.shared.record(id: matchID)?.workout = report
        } else {
            context.insert(WorkoutSessionRecord(matchID: nil, date: date, summary: report))
        }
        AppDatabase.save()
        reload()
    }
}
