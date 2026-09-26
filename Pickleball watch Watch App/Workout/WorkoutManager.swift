//
//  WorkoutManager.swift
//  Pickleball watch Watch App
//
//  HealthKit workout for the match: heart rate, energy and personal
//  heart-rate zones (replacing the old fixed 160 bpm "fatigue" flag), plus
//  wrist-motion shot detection, which is labelled beta everywhere.
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
    private(set) var heartRate: Double = 0
    private(set) var currentZone: HeartRateZones.Zone?
    private(set) var calories: Double = 0
    private(set) var shots = WorkoutReport.ShotCounts(forehand: 0, backhand: 0, volley: 0, serve: 0, longestRally: 0)
    private(set) var authorizationDenied = false

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
    @ObservationIgnored private var accumulator = ZoneAccumulator(zones: HeartRateZones(age: 35))
    @ObservationIgnored private var currentRally = 0

    private override init() {
        super.init()
    }

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

    // MARK: - Lifecycle

    func start(sport: Sport, matchID: UUID) {
        if isRunning, self.matchID == matchID { return }
        if isRunning { _ = stop() }
        self.matchID = matchID
        guard HKHealthStore.isHealthDataAvailable() else { return }
        requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.authorizationDenied = true
                return
            }
            self.authorizationDenied = false
            self.beginSession(sport: sport)
        }
    }

    /// Ends the workout and returns what was measured.
    @discardableResult
    func stop() -> WorkoutReport? {
        guard isRunning, let startDate else { return nil }
        motion.stopDeviceMotionUpdates()
        let endDate = Date()
        session?.end()
        let builder = self.builder
        builder?.endCollection(withEnd: endDate) { _, error in
            if let error { print("Workout: endCollection failed: \(error.localizedDescription)") }
            builder?.finishWorkout { _, error in
                if let error { print("Workout: finishWorkout failed: \(error.localizedDescription)") }
            }
        }
        self.builder = nil
        self.session = nil
        isRunning = false
        currentZone = nil

        return WorkoutReport(
            duration: endDate.timeIntervalSince(startDate),
            averageHeartRate: accumulator.averageBPM,
            peakHeartRate: accumulator.peakBPM,
            calories: calories,
            secondsInZone: accumulator.seconds,
            maxHeartRate: accumulator.zones.maxHeartRate,
            shots: shots.total > 0 ? shots : nil
        )
    }

    private func beginSession(sport: Sport) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sport == .pickleball ? .pickleball : .paddleSports
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let now = Date()
            startDate = now
            accumulator = ZoneAccumulator(zones: zones())
            calories = 0
            heartRate = 0
            shots = WorkoutReport.ShotCounts(forehand: 0, backhand: 0, volley: 0, serve: 0, longestRally: 0)
            currentRally = 0
            detector.reset()

            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, error in
                if let error { print("Workout: beginCollection failed: \(error.localizedDescription)") }
            }
            isRunning = true
            startMotion()
        } catch {
            print("Workout: could not start session: \(error.localizedDescription)")
        }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        let detector = self.detector
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
            guard let data, error == nil, let event = detector.process(data) else { return }
            Task { @MainActor in self?.record(event) }
        }
    }

    private func record(_ event: ShotDetector.Event) {
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

    private nonisolated func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKCharacteristicType(.dateOfBirth)
        ]
        HKHealthStore().requestAuthorization(toShare: share, read: read) { success, error in
            if let error { print("Workout: authorization error: \(error.localizedDescription)") }
            Task { @MainActor in completion(success) }
        }
    }

    fileprivate func ingest(heartRate bpm: Double, calories energy: Double?) {
        if bpm > 0 {
            heartRate = bpm
            accumulator.add(bpm: bpm, at: Date())
            currentZone = accumulator.currentZone
        }
        if let energy { calories = energy }
    }
}

// MARK: - HealthKit delegates

extension WorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout: session failed: \(error.localizedDescription)")
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var bpm: Double = 0
        var energy: Double?
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(heartRateType) {
            bpm = workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
        }
        if collectedTypes.contains(energyType) {
            energy = workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        Task { @MainActor in self.ingest(heartRate: bpm, calories: energy) }
    }
}
