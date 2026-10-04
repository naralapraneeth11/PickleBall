//
//  WorkoutManager.swift
//  Pickleball watch Watch App
//
//  The match's HealthKit workout: heart rate, energy and personal
//  heart-rate zones, plus optional wrist-motion shot estimates (beta).
//
//  The workout is separate from scoring. The match journal is the
//  authority for the score and HealthKit for the workout samples, so a
//  denied permission, a workout another app takes over or a failed save
//  never touches the score.
//
//  • One workout per match (WorkoutLedger, saved to disk). A relaunch mid-
//    match recovers the running session instead of starting a second one.
//  • Mirrored to the iPhone: compact live metrics, throttled well under
//    HealthKit's remote-session limit.
//  • Pauses with the match.
//  • Crash recovery (`handleActiveWorkoutRecovery`) reconciles the
//    recovered session with the journal: keep recording if the match is
//    still on, otherwise save it.
//  • Finalization waits for each HealthKit step (stop → end collection →
//    finish → end) and retries; the summary is saved before it starts and
//    sent to the iPhone even if HealthKit fails.
//

import Foundation
import Observation
import CoreMotion
import HealthKit
import CourtKit

enum ShotType: String, Codable { case forehand, backhand, volley, serve, unknown }

/// Threshold-based swing classifier. Beta: not validated on real players.
private final class ShotDetector {
    struct Event { let type: ShotType; let date: Date; let rallyReset: Bool }
    private var lastShotTime = Date.distantPast
    private let shotThreshold = 2.5, minTimeBetweenShots = 0.35, rallyPauseThreshold = 2.0
    private let forehandRotationMin = -1.2, backhandRotationMin = 1.2, volleyAccelThreshold = 1.8, servePitchThreshold = 1.5

    func reset() { lastShotTime = .distantPast }

    func process(_ motion: CMDeviceMotion) -> Event? {
        let a = motion.userAcceleration
        let totalAccel = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        guard totalAccel > shotThreshold else { return nil }
        let now = Date(), sinceLast = now.timeIntervalSince(lastShotTime)
        guard sinceLast > minTimeBetweenShots else { return nil }
        let rallyReset = sinceLast > rallyPauseThreshold
        lastShotTime = now
        let rotationZ = motion.rotationRate.z, accelY = a.y, pitch = motion.attitude.pitch
        let type: ShotType
        if accelY > servePitchThreshold && pitch > 0.8 { type = .serve }
        else if abs(rotationZ) < 0.8 && totalAccel > volleyAccelThreshold { type = .volley }
        else if rotationZ < forehandRotationMin { type = .forehand }
        else if rotationZ > backhandRotationMin { type = .backhand }
        else { type = .unknown }
        return Event(type: type, date: now, rallyReset: rallyReset)
    }
}

@MainActor
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    private(set) var isRunning = false
    private(set) var isPaused = false
    /// Latest heart rate; 0 when there is no reading.
    private(set) var heartRate: Double = 0
    private(set) var currentZone: HeartRateZones.Zone?
    private(set) var calories: Double = 0
    private(set) var shots = WorkoutReport.ShotCounts(forehand: 0, backhand: 0, volley: 0, serve: 0, longestRally: 0)
    /// Health didn't allow saving workouts. Scoring is unaffected.
    private(set) var authorizationDenied = false
    /// Recording stopped without our asking (another workout took over).
    private(set) var recordingStopped = false
    private(set) var ledger: WorkoutLedger

    // Settings (Watch-local).
    /// Off = score-only mode: no HealthKit session at all.
    var recordsWorkouts: Bool { didSet { defaults.set(recordsWorkouts, forKey: Keys.records) } }
    var isIndoor: Bool { didSet { defaults.set(isIndoor, forKey: Keys.indoor) } }
    /// Experimental swing estimates from wrist motion.
    var estimatesShots: Bool { didSet { defaults.set(estimatesShots, forKey: Keys.shots) } }

    /// Hands a finished workout's summary to the iPhone. Returns true once
    /// it is queued (WatchConnectivity keeps it across relaunches).
    @ObservationIgnored var onReport: ((_ matchID: UUID, _ date: Date, _ report: WorkoutReport) -> Bool)?

    private enum Keys {
        static let records = "workout.records"
        static let indoor = "workout.indoor"
        static let shots = "workout.shots"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let detector = ShotDetector()
    @ObservationIgnored private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.pickleball.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var matchID: UUID?
    /// Set while we end the session ourselves, so `.ended` isn't mistaken
    /// for an interruption.
    @ObservationIgnored private var isEnding = false
    @ObservationIgnored private var accumulator = ZoneAccumulator(zones: HeartRateZones(age: 35))
    @ObservationIgnored private var currentRally = 0
    @ObservationIgnored private var throttle = MetricsThrottle(interval: 5)
    @ObservationIgnored private var lifecycle: Task<Void, Never>?

    private static var ledgerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workout", isDirectory: true)
            .appendingPathComponent("ledger.json")
    }

    private override init() {
        let defaults = UserDefaults.standard
        recordsWorkouts = defaults.object(forKey: Keys.records) as? Bool ?? true
        isIndoor = defaults.bool(forKey: Keys.indoor)
        estimatesShots = defaults.object(forKey: Keys.shots) as? Bool ?? true
        var ledger = (try? Data(contentsOf: Self.ledgerURL)).flatMap { try? JSONDecoder().decode(WorkoutLedger.self, from: $0) }
            ?? WorkoutLedger()
        ledger.compact(olderThan: 7 * 86_400, now: Date())
        self.ledger = ledger
        super.init()
    }

    /// Where a match's workout stands (for the result screen).
    func state(for matchID: UUID) -> WorkoutEntry.State? { ledger.entry(matchID)?.state }

    /// Personal zones: Health date of birth first, then the phone profile's
    /// age, then a neutral default.
    private func zones() -> HeartRateZones {
        var age: Int?
        if let components = try? healthStore.dateOfBirthComponents(),
           let year = components.year {
            age = Calendar.current.component(.year, from: Date()) - year
        }
        return HeartRateZones(age: age ?? WatchMatchSession.shared.preferences.age ?? 35)
    }

    // MARK: - Lifecycle (serialized)

    /// Runs lifecycle steps one at a time, in order.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = lifecycle
        lifecycle = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Records a workout for a match, unless one is already running or
    /// was already recorded for it.
    func start(sport: Sport, matchID: UUID) {
        enqueue { await self.begin(sport: sport, matchID: matchID) }
    }

    /// Ends and saves the match's workout. `sendsReport` is false for a
    /// match that was thrown away.
    func finish(matchID: UUID, sendsReport: Bool = true) {
        enqueue { await self.finalize(matchID: matchID, sendsReport: sendsReport) }
    }

    /// The system relaunched us with a workout still running after a crash.
    func recoverAfterCrash() {
        enqueue { _ = await self.recover(expecting: nil) }
    }

    func pause() {
        guard isRunning, !isPaused, let session else { return }
        session.pause()
        isPaused = true
        sendMetrics(force: true)
    }

    func resume() {
        guard isRunning, isPaused, let session else { return }
        session.resume()
        isPaused = false
        sendMetrics(force: true)
    }

    private func begin(sport: Sport, matchID: UUID) async {
        guard recordsWorkouts, HKHealthStore.isHealthDataAvailable() else { return }
        switch ledger.decision(forBeginning: matchID) {
        case .alreadyRecorded:
            return
        case .alreadyActive:
            if session != nil, self.matchID == matchID { return }
            if await recover(expecting: matchID) { return }
            // The session didn't survive (the Watch restarted): start over.
            ledger.discardLostSession(matchID)
            saveLedger()
        case .otherActive(let other):
            await finalize(matchID: other, sendsReport: true)
        case .start:
            break
        }
        guard await authorize() else {
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        beginSession(sport: sport, matchID: matchID)
    }

    /// Asks for Health access. Success of the request doesn't mean access
    /// was granted, so check write authorization afterwards.
    private func authorize() async -> Bool {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKCharacteristicType(.dateOfBirth)
        ]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.requestAuthorization(toShare: share, read: read) { _, _ in continuation.resume() }
        }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    private func beginSession(sport: Sport, matchID: UUID) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sport == .pickleball ? .pickleball : .paddleSports
        configuration.locationType = isIndoor ? .indoor : .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            let now = Date()
            ledger.begin(matchID: matchID, sport: sport, isIndoor: isIndoor, at: now)
            saveLedger()
            bind(session, builder, matchID: matchID, startDate: now)
            resetMetrics()

            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, error in
                if let error { print("Workout: beginCollection failed: \(error.localizedDescription)") }
            }
            startMirroring(session)
            startMotion()
        } catch {
            print("Workout: could not start session: \(error.localizedDescription)")
        }
    }

    private func bind(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder, matchID: UUID?, startDate: Date) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        self.matchID = matchID
        self.startDate = startDate
        isEnding = false
        isRunning = true
        isPaused = false
        recordingStopped = false
        throttle.reset()
    }

    private func unbind() {
        motion.stopDeviceMotionUpdates()
        session = nil
        builder = nil
        matchID = nil
        startDate = nil
        isRunning = false
        isPaused = false
        currentZone = nil
        heartRate = 0
    }

    private func resetMetrics() {
        accumulator = ZoneAccumulator(zones: zones())
        calories = 0
        heartRate = 0
        shots = WorkoutReport.ShotCounts(forehand: 0, backhand: 0, volley: 0, serve: 0, longestRally: 0)
        currentRally = 0
        detector.reset()
    }

    /// Mirrors the workout to the iPhone, which may launch in the
    /// background to receive it. Failing is fine: the match journal still
    /// syncs over WatchConnectivity.
    private func startMirroring(_ session: HKWorkoutSession) {
        Task { @MainActor in
            do {
                try await session.startMirroringToCompanionDevice()
            } catch {
                print("Workout: mirroring unavailable: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recovery

    /// Picks up a workout HealthKit kept running through a crash. Returns
    /// true if it is now recording `expecting` (or anything, when nil).
    private func recover(expecting: UUID?) async -> Bool {
        if session != nil { return expecting == nil || matchID == expecting }
        let recovered: HKWorkoutSession? = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                if let error { print("Workout: recovery failed: \(error.localizedDescription)") }
                continuation.resume(returning: session)
            }
        }
        guard let recovered else { return false }
        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: recovered.workoutConfiguration)
        let candidate = ledger.active?.matchID
        let status = await journalStatus(candidate)
        let started = recovered.startDate ?? candidate.flatMap { ledger.entry($0)?.startedAt } ?? Date()

        switch ledger.recoveryAction(journalStatus: status) {
        case .resume(let id, let paused):
            bind(recovered, builder, matchID: id, startDate: started)
            // Earlier samples are in HealthKit; the zone summary restarts.
            accumulator = ZoneAccumulator(zones: zones())
            if paused {
                if recovered.state != .paused { recovered.pause() }
                isPaused = true
            } else if recovered.state == .paused {
                recovered.resume()
            }
            startMirroring(recovered)
            startMotion()
            return expecting == nil || id == expecting
        case .finalize(let id):
            bind(recovered, builder, matchID: id, startDate: started)
            await finalize(matchID: id, sendsReport: status != .abandoned)
            return false
        }
    }

    private func journalStatus(_ matchID: UUID?) async -> MatchJournal.Status? {
        guard let matchID, let coordinator = WatchMatchSession.shared.coordinator else { return nil }
        return await coordinator.journal(matchID)?.status
    }

    // MARK: - Finalization

    private func finalize(matchID requested: UUID?, sendsReport: Bool) async {
        guard let session, let builder, requested == nil || matchID == requested else {
            // Nothing running for it: a session lost to a Watch restart.
            if let requested, ledger.entry(requested)?.state == .active {
                ledger.markInterrupted(requested, report: nil, at: Date())
                saveLedger()
            }
            return
        }
        let id = matchID
        let end = Date()
        motion.stopDeviceMotionUpdates()
        let report = makeReport(end: end)
        if let id {
            // The summary is safe on disk before HealthKit does anything.
            ledger.markFinishing(id, report: sendsReport ? report : nil, at: end)
            saveLedger()
            sendPendingReports()
        }
        isEnding = true
        isRunning = false
        currentZone = nil

        session.stopActivity(with: end)
        await wait(for: .stopped, on: session, timeout: 10)
        do {
            try await endCollection(builder, at: end)
        } catch {
            print("Workout: endCollection failed: \(error.localizedDescription)")
        }
        var attempt = 0
        while true {
            do {
                let workoutID = try await finishWorkout(builder)
                if let id { ledger.markSaved(id, workoutID: workoutID) }
                break
            } catch {
                print("Workout: finishWorkout failed: \(error.localizedDescription)")
                attempt += 1
                let retry = id.map { ledger.markAttemptFailed($0) } ?? (attempt < WorkoutLedger.maxAttempts)
                guard retry else { break }
                try? await Task.sleep(for: .seconds(Double(attempt * 2)))
            }
        }
        saveLedger()
        session.end()
        unbind()
    }

    private func wait(for state: HKWorkoutSessionState, on session: HKWorkoutSession, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while session.state != state, session.state != .ended, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func endCollection(_ builder: HKLiveWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: date) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func finishWorkout(_ builder: HKLiveWorkoutBuilder) async throws -> UUID? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID?, Error>) in
            builder.finishWorkout { workout, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: workout?.uuid) }
            }
        }
    }

    /// Recording stopped without our asking. Keep what was measured and
    /// try to save it; scoring carries on.
    private func interrupted() {
        guard let session, let builder else { return }
        let id = matchID
        let now = Date()
        if let id {
            ledger.markInterrupted(id, report: makeReport(end: now), at: now)
            saveLedger()
            sendPendingReports()
        }
        recordingStopped = true
        unbind()
        enqueue {
            do {
                try await self.endCollection(builder, at: now)
                let workoutID = try await self.finishWorkout(builder)
                if let id { self.ledger.markSaved(id, workoutID: workoutID) }
                self.saveLedger()
            } catch {
                print("Workout: couldn't save the interrupted workout: \(error.localizedDescription)")
            }
            session.end()
        }
    }

    // MARK: - Summary

    /// What was measured. HealthKit's own statistics first (they survive a
    /// crash recovery), our running totals otherwise.
    private func makeReport(end: Date) -> WorkoutReport {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartStats = builder?.statistics(for: HKQuantityType(.heartRate))
        let average = heartStats?.averageQuantity()?.doubleValue(for: bpm) ?? accumulator.averageBPM
        let peak = heartStats?.maximumQuantity()?.doubleValue(for: bpm) ?? accumulator.peakBPM
        let energy = builder?.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? calories
        let elapsed = builder?.elapsedTime ?? 0
        return WorkoutReport(
            duration: elapsed > 0 ? elapsed : end.timeIntervalSince(startDate ?? end),
            averageHeartRate: average,
            peakHeartRate: peak,
            calories: energy,
            secondsInZone: accumulator.seconds,
            maxHeartRate: accumulator.zones.maxHeartRate,
            shots: shots.total > 0 ? shots : nil
        )
    }

    /// Sends summaries that haven't been handed over yet (also after a
    /// relaunch).
    func sendPendingReports() {
        guard let onReport else { return }
        var changed = false
        for entry in ledger.reportsToSend {
            guard let report = entry.report, onReport(entry.matchID, entry.startedAt, report) else { continue }
            ledger.markReportQueued(entry.matchID)
            changed = true
        }
        if changed { saveLedger() }
    }

    private func saveLedger() {
        let url = Self.ledgerURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
        } catch {
            print("Workout: couldn't save the ledger: \(error.localizedDescription)")
        }
    }

    // MARK: - Live metrics

    private func sendMetrics(force: Bool = false) {
        guard let session, isRunning else { return }
        let metrics = WorkoutLiveMetrics(matchID: matchID, heartRate: heartRate > 0 ? heartRate : nil,
                                         activeEnergy: calories > 0 ? calories : nil,
                                         elapsed: builder?.elapsedTime ?? 0, isPaused: isPaused, sampledAt: Date())
        if force { throttle.reset() }
        guard throttle.shouldSend(metrics, now: Date()) else { return }
        session.sendToRemoteWorkoutSession(data: metrics.encoded) { _, _ in }
    }

    // MARK: - Motion (beta)

    private func startMotion() {
        guard estimatesShots, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        let detector = self.detector
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
            guard let data, error == nil, let event = detector.process(data) else { return }
            Task { @MainActor in self?.record(event) }
        }
    }

    private func record(_ event: ShotDetector.Event) {
        guard !isPaused else { return }
        if event.rallyReset { currentRally = 0 }
        currentRally += 1
        shots.longestRally = max(shots.longestRally, currentRally)
        switch event.type {
        case .serve: shots.serve += 1
        case .volley: shots.volley += 1
        case .forehand: shots.forehand += 1
        case .backhand: shots.backhand += 1
        case .unknown: break
        }
    }

    fileprivate func ingest(heartRate bpm: Double, calories energy: Double?, from builder: HKLiveWorkoutBuilder) {
        guard builder === self.builder else { return }
        if bpm > 0 {
            heartRate = bpm
            accumulator.add(bpm: bpm, at: Date())
            currentZone = accumulator.currentZone
        }
        if let energy { calories = energy }
        sendMetrics()
    }

    fileprivate func sessionChanged(_ session: HKWorkoutSession, to state: HKWorkoutSessionState) {
        guard session === self.session else { return }
        if state == .ended, !isEnding { interrupted() }
    }

    fileprivate func sessionFailed(_ session: HKWorkoutSession) {
        guard session === self.session, !isEnding else { return }
        interrupted()
    }
}

// MARK: - HealthKit delegates

extension WorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.sessionChanged(workoutSession, to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout: session failed: \(error.localizedDescription)")
        Task { @MainActor in self.sessionFailed(workoutSession) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let bpm: Double = collectedTypes.contains(heartRateType)
            ? workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            : 0
        let energy: Double? = collectedTypes.contains(energyType)
            ? workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        Task { @MainActor in self.ingest(heartRate: bpm, calories: energy, from: workoutBuilder) }
    }
}
