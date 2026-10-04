//
//  WorkoutLedger.swift
//  CourtKit
//
//  The Watch's durable record of match workouts, kept apart from the match
//  journal: the journal is the authority for the score, HealthKit for the
//  workout samples. The ledger makes sure there is at most one workout per
//  match, keeps the final summary through a relaunch until it has been
//  handed to WatchConnectivity, and decides what to do with a workout the
//  system recovers after a crash.
//

import Foundation

public struct WorkoutEntry: Codable, Hashable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable {
        /// The workout session is running (or paused).
        case active
        /// The score is complete; HealthKit is still saving the workout.
        case finishing
        /// HealthKit saved the workout.
        case saved
        /// Saving failed or recording stopped early. The summary is kept.
        case failed
    }

    public var matchID: UUID
    public var sport: Sport
    public var isIndoor: Bool
    public var startedAt: Date
    public var state: State
    public var endedAt: Date?
    /// What was measured, persisted before HealthKit finalization starts.
    public var report: WorkoutReport?
    /// The saved HealthKit workout.
    public var workoutID: UUID?
    public var attempts: Int
    /// The report has been handed to WatchConnectivity (which keeps it
    /// queued across relaunches until delivered).
    public var reportQueued: Bool

    public var id: UUID { matchID }

    public init(matchID: UUID, sport: Sport, isIndoor: Bool, startedAt: Date) {
        self.matchID = matchID
        self.sport = sport
        self.isIndoor = isIndoor
        self.startedAt = startedAt
        self.state = .active
        self.attempts = 0
        self.reportQueued = false
    }
}

public struct WorkoutLedger: Codable, Hashable, Sendable {
    public private(set) var entries: [UUID: WorkoutEntry] = [:]

    public init() {}

    /// Finalization attempts before giving up (the summary is still kept).
    public static let maxAttempts = 3

    public func entry(_ matchID: UUID) -> WorkoutEntry? { entries[matchID] }

    /// The running workout, if any. There is never more than one.
    public var active: WorkoutEntry? {
        entries.values.filter { $0.state == .active }.max { $0.startedAt < $1.startedAt }
    }

    // MARK: Starting

    public enum BeginDecision: Equatable, Sendable {
        /// Start a new HealthKit session.
        case start
        /// This match already has a running workout: recover or keep it.
        case alreadyActive
        /// This match's workout already ended: never record it twice.
        case alreadyRecorded
        /// Another match's workout is running; end it first.
        case otherActive(UUID)
    }

    public func decision(forBeginning matchID: UUID) -> BeginDecision {
        if let existing = entries[matchID] {
            return existing.state == .active ? .alreadyActive : .alreadyRecorded
        }
        if let other = active { return .otherActive(other.matchID) }
        return .start
    }

    /// Records a new workout. Returns false (and changes nothing) unless
    /// `decision(forBeginning:)` is `.start`.
    @discardableResult
    public mutating func begin(matchID: UUID, sport: Sport, isIndoor: Bool, at date: Date) -> Bool {
        guard decision(forBeginning: matchID) == .start else { return false }
        entries[matchID] = WorkoutEntry(matchID: matchID, sport: sport, isIndoor: isIndoor, startedAt: date)
        return true
    }

    /// A workout that could not be recovered after a crash: forget the
    /// session so a new one can start, but keep nothing that was saved.
    public mutating func discardLostSession(_ matchID: UUID) {
        guard entries[matchID]?.state == .active else { return }
        entries[matchID] = nil
    }

    // MARK: Ending

    /// The score is complete: keep the summary before HealthKit saves.
    public mutating func markFinishing(_ matchID: UUID, report: WorkoutReport?, at date: Date) {
        guard var entry = entries[matchID], entry.state == .active else { return }
        entry.state = .finishing
        entry.endedAt = date
        entry.report = report
        entries[matchID] = entry
    }

    public mutating func markSaved(_ matchID: UUID, workoutID: UUID?) {
        guard var entry = entries[matchID], entry.state != .saved else { return }
        entry.state = .saved
        entry.workoutID = workoutID
        entries[matchID] = entry
    }

    /// One failed save attempt. Returns true if another attempt is allowed.
    @discardableResult
    public mutating func markAttemptFailed(_ matchID: UUID) -> Bool {
        guard var entry = entries[matchID], entry.state != .saved else { return false }
        entry.attempts += 1
        let retry = entry.attempts < Self.maxAttempts
        if !retry { entry.state = .failed }
        entries[matchID] = entry
        return retry
    }

    /// Recording stopped without our asking (another workout took over the
    /// Watch, or HealthKit failed). Scoring carries on.
    public mutating func markInterrupted(_ matchID: UUID, report: WorkoutReport?, at date: Date) {
        guard var entry = entries[matchID], entry.state == .active || entry.state == .finishing else { return }
        entry.state = .failed
        entry.endedAt = entry.endedAt ?? date
        entry.report = entry.report ?? report
        entries[matchID] = entry
    }

    public mutating func markReportQueued(_ matchID: UUID) {
        entries[matchID]?.reportQueued = true
    }

    /// Ended workouts whose summary hasn't been handed over yet.
    public var reportsToSend: [WorkoutEntry] {
        entries.values
            .filter { $0.state != .active && $0.report != nil && !$0.reportQueued }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: Recovery

    public enum RecoveryAction: Equatable, Sendable {
        /// The match is still being played: keep recording.
        case resume(matchID: UUID, paused: Bool)
        /// The match ended (or is unknown): save the workout now.
        case finalize(matchID: UUID?)
    }

    /// What to do with a workout session the system recovered, given the
    /// match journal's view of the match. HealthKit recovery doesn't bring
    /// back scoring events; the journal is the authority for those.
    public func recoveryAction(journalStatus: MatchJournal.Status?) -> RecoveryAction {
        guard let entry = active ?? entries.values.first(where: { $0.state == .finishing }) else {
            return .finalize(matchID: nil)
        }
        guard entry.state == .active else { return .finalize(matchID: entry.matchID) }
        switch journalStatus {
        case .live: return .resume(matchID: entry.matchID, paused: false)
        case .paused: return .resume(matchID: entry.matchID, paused: true)
        case .finished, .abandoned, nil: return .finalize(matchID: entry.matchID)
        }
    }

    // MARK: Housekeeping

    /// Drops settled entries (saved or failed, summary handed over) older
    /// than `age`. Active and unsent entries are always kept.
    public mutating func compact(olderThan age: TimeInterval, now: Date) {
        entries = entries.filter { _, entry in
            guard entry.state == .saved || entry.state == .failed, entry.reportQueued || entry.report == nil else { return true }
            return now.timeIntervalSince(entry.endedAt ?? entry.startedAt) < age
        }
    }
}

// MARK: - Live metrics over HealthKit mirroring

/// The compact live snapshot the Watch sends to the iPhone's mirrored
/// workout session. Match history never travels this way: mirroring ends
/// with the workout and has transfer limits.
public struct WorkoutLiveMetrics: Codable, Hashable, Sendable {
    public var matchID: UUID?
    /// Beats per minute; nil when there's no reading (never zero).
    public var heartRate: Double?
    /// Kilocalories so far; nil when unavailable.
    public var activeEnergy: Double?
    public var elapsed: TimeInterval
    public var isPaused: Bool
    /// When the readings were taken on the Watch.
    public var sampledAt: Date

    public init(matchID: UUID?, heartRate: Double?, activeEnergy: Double?, elapsed: TimeInterval,
                isPaused: Bool, sampledAt: Date) {
        self.matchID = matchID
        self.heartRate = heartRate
        self.activeEnergy = activeEnergy
        self.elapsed = elapsed
        self.isPaused = isPaused
        self.sampledAt = sampledAt
    }

    private enum CodingKeys: String, CodingKey {
        case matchID = "m", heartRate = "hr", activeEnergy = "kc", elapsed = "el", isPaused = "p", sampledAt = "at"
    }

    public var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data) -> WorkoutLiveMetrics? {
        try? JSONDecoder().decode(WorkoutLiveMetrics.self, from: data)
    }
}

/// Keeps mirrored metrics well under HealthKit's remote-session budget
/// (100 KB per 10 s): at most one snapshot per interval, sooner only when
/// the pause state changes.
public struct MetricsThrottle: Sendable {
    public let interval: TimeInterval
    private var lastSent: Date?
    private var lastPaused: Bool?

    public init(interval: TimeInterval = 5) {
        self.interval = interval
    }

    public mutating func shouldSend(_ metrics: WorkoutLiveMetrics, now: Date) -> Bool {
        let pauseChanged = lastPaused != nil && lastPaused != metrics.isPaused
        guard pauseChanged || lastSent.map({ now.timeIntervalSince($0) >= interval }) ?? true else { return false }
        lastSent = now
        lastPaused = metrics.isPaused
        return true
    }

    public mutating func reset() {
        lastSent = nil
        lastPaused = nil
    }
}
