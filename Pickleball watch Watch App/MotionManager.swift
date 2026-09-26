//
//  MotionManager.swift
//  Pickleball watch Watch App
//
import Foundation
import Combine
import CoreMotion
import WatchKit
import HealthKit

enum ShotType: String, Codable { case forehand, backhand, volley, serve, unknown }

private final class ShotDetector {
    struct Event { let type: ShotType; let date: Date; let rallyReset: Bool }
    private var lastShotTime = Date.distantPast
    private let shotThreshold: Double = 2.5, minTimeBetweenShots: Double = 0.35, rallyPauseThreshold: Double = 2.0
    private let forehandRotationMin: Double = -1.2, backhandRotationMin: Double = 1.2, volleyAccelThreshold: Double = 1.8, servePitchThreshold: Double = 1.5

    func reset() { lastShotTime = .distantPast }
    func process(_ motion: CMDeviceMotion) -> Event? {
        let a = motion.userAcceleration
        let totalAccel = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        guard totalAccel > shotThreshold else { return nil }
        let now = Date(), sinceLast = now.timeIntervalSince(lastShotTime)
        guard sinceLast > minTimeBetweenShots else { return nil }
        let rallyReset = sinceLast > rallyPauseThreshold
        lastShotTime = now
        let rotationZ = motion.rotationRate.z, accelY = motion.userAcceleration.y, pitch = motion.attitude.pitch
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
final class MotionManager: NSObject, ObservableObject {
    @Published var isTracking = false
    @Published var currentShotCount = 0
    @Published var lastShotType = ShotType.unknown
    @Published var forehandCount = 0
    @Published var backhandCount = 0
    @Published var volleyCount = 0
    @Published var serveCount = 0
    @Published var currentRallyLength = 0
    @Published var maxRallyLength = 0
    @Published var avgHeartRate = 0.0
    @Published var caloriesBurned = 0.0
    @Published var fatigueOnset: TimeInterval?
    @Published var workoutAuthDenied = false

    private let motionManager = CMMotionManager()
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?, builder: HKLiveWorkoutBuilder?, gameStartTime: Date?
    private let detector = ShotDetector()
    private let motionQueue: OperationQueue = { let q = OperationQueue(); q.name = "com.pickleball.motion"; q.maxConcurrentOperationCount = 1; return q }()
    private let fatigueHrThreshold: Double = 160.0

    func startTracking() {
        guard motionManager.isDeviceMotionAvailable, HKHealthStore.isHealthDataAvailable() else { return }
        requestHealthAuthorization { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else { self.workoutAuthDenied = true; return }
                self.workoutAuthDenied = false; self.beginWorkoutSession(); self.resetCounts()
                self.gameStartTime = Date(); self.detector.reset(); self.isTracking = true
                self.motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                self.motionManager.startDeviceMotionUpdates(to: self.motionQueue) { [weak self] motion, error in
                    guard let self, let motion, error == nil, let event = self.detector.process(motion) else { return }
                    Task { @MainActor in self.record(event) }
                }
            }
        }
    }

    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
        let endDate = Date()
        workoutSession?.end()
        builder?.endCollection(withEnd: endDate) { [weak self] _, error in
            if let error { print("MotionManager: endCollection failed: \(error.localizedDescription)") }
            Task { @MainActor [weak self] in
                self?.builder?.finishWorkout { _, error in
                    if let error { print("MotionManager: finishWorkout failed: \(error.localizedDescription)") }
                    Task { @MainActor [weak self] in self?.builder = nil; self?.workoutSession = nil }
                }
            }
        }
        isTracking = false
    }

    // PRO: Extended to accept serve stats from WatchMatchSync
    func gameCompletePayload(matchID: UUID, servePointsPlayed: Int = 0, servePointsWon: Int = 0) -> [String: Any]? {
        guard let start = gameStartTime else { return nil }
        return [
            "type": "gameComplete", "matchID": matchID.uuidString, "date": start.timeIntervalSince1970,
            "duration": Date().timeIntervalSince(start), "totalShots": currentShotCount,
            "forehands": forehandCount, "backhands": backhandCount, "volleys": volleyCount, "serves": serveCount,
            "maxRally": maxRallyLength, "avgHR": avgHeartRate, "calories": caloriesBurned,
            "fatigueOnset": fatigueOnset ?? 0.0,
            "servePointsPlayed": servePointsPlayed, "servePointsWon": servePointsWon
        ]
    }

    private func record(_ event: ShotDetector.Event) {
        if event.rallyReset { currentRallyLength = 0 }
        currentShotCount += 1; currentRallyLength += 1; maxRallyLength = max(maxRallyLength, currentRallyLength)
        switch event.type {
        case .serve: serveCount += 1
        case .volley: volleyCount += 1
        case .forehand: forehandCount += 1
        case .backhand: backhandCount += 1
        case .unknown: break
        }
        lastShotType = event.type
        WKInterfaceDevice.current().play(.click)
        if avgHeartRate > fatigueHrThreshold && fatigueOnset == nil {
            fatigueOnset = event.date.timeIntervalSince(gameStartTime ?? event.date)
        }
    }

    private nonisolated func requestHealthAuthorization(completion: @escaping (Bool) -> Void) {
        let types = Set([HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)])
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
            if let error { print("MotionManager: HealthKit auth error: \(error.localizedDescription)") }
            completion(success)
        }
    }

    private func beginWorkoutSession() {
        let config = HKWorkoutConfiguration(); config.activityType = .pickleball; config.locationType = .outdoor
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            workoutSession?.delegate = self; builder?.delegate = self
            workoutSession?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { _, error in
                if let error { print("MotionManager: beginCollection failed: \(error.localizedDescription)") }
            }
        } catch { print("MotionManager: failed to create workout session: \(error.localizedDescription)") }
    }

    private func resetCounts() {
        currentShotCount = 0; lastShotType = .unknown; forehandCount = 0; backhandCount = 0
        volleyCount = 0; serveCount = 0; currentRallyLength = 0; maxRallyLength = 0
        avgHeartRate = 0.0; caloriesBurned = 0.0; fatigueOnset = nil
    }
}

extension MotionManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) { print("MotionManager: workout session failed: \(error.localizedDescription)") }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType, let stats = self.builder?.statistics(for: quantityType) else { continue }
                if quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue {
                    self.avgHeartRate = stats.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                } else if quantityType.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue {
                    self.caloriesBurned = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                }
            }
        }
    }
}
