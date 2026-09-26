//
//  WatchConnectivityManager.swift
//  PickleBall
//
//  Phone-side sync manager. Single owner of WCSession.delegate on iOS.
//

import Foundation
import Combine
import WatchConnectivity
import HealthKit

// MARK: - GameSession

struct GameSession: Codable, Equatable {
    /// Stable identifier generated on the watch when a match starts.
    /// Used to merge gameComplete shot stats with the matchState stub.
    /// Optional for backward compat with pre-existing entries.
    var id: UUID? = nil
    var matchID: UUID?

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
    var servePointsPlayed: Int? = nil
    var servePointsWon: Int? = nil
    // matchID + date already expected
}

// MARK: - WatchConnectivityManager

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    /// Most recent gameComplete payload or HealthKit fetch. Drives the
    /// shutter panel on MainMenu / StatsView.
    @Published var recentGame: GameSession?

    /// Live match state from a phone-initiated match (case 1).
    /// GameSceneView observes this to mirror watch-side score updates
    /// in real time.
    @Published var liveMatchState: MatchState?

    /// In-memory tracker for the currently active watch-initiated match.
    private var pendingWatchMatch: PendingMatch?

    private struct PendingMatch {
        let id: UUID
        let startDate: Date
    }

    private var session: WCSession?

    /// Throttle for fetchRecentFromHealthKit so onAppear doesn't hammer
    /// HealthKit on every view appearance.
    private var lastHealthFetch: Date = .distantPast
    private let healthFetchInterval: TimeInterval = 30

    /// Serial background queue for JSON encode/decode + UserDefaults I/O.
    /// Keeps history persistence off the main thread.
    private let ioQueue = DispatchQueue(label: "com.pickleball.watchconnectivity.io", qos: .utility)

    #if os(iOS)
    var isWatchPaired: Bool { session?.isPaired ?? false }
    var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
    var isWatchReachable: Bool { session?.isReachable ?? false }
    #else
    var isWatchPaired: Bool { false }
    var isWatchAppInstalled: Bool { false }
    var isWatchReachable: Bool { false }
    #endif

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Send phone-originated match state to the watch.
    /// updateApplicationContext is set first as the guaranteed-delivery
    /// floor; sendMessage piggybacks for low-latency when reachable.
    func sendPhoneMatchState(_ state: MatchState) {
        guard let session else { return }
        let payload = state.dictionary

        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - HealthKit ────────────────────────────────────────

    func fetchRecentFromHealthKit(completion: @escaping (GameSession?, Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion(nil, false) }
            return
        }

        // Throttle — multiple onAppear calls in quick succession should be no-ops
        if Date().timeIntervalSince(lastHealthFetch) < healthFetchInterval,
           let cached = recentGame {
            DispatchQueue.main.async { completion(cached, true) }
            return
        }
        lastHealthFetch = Date()

        let healthStore = HKHealthStore()
        let typesToRead: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]

        healthStore.requestAuthorization(toShare: [], read: typesToRead) { [weak self] success, _ in
            guard let self else { return }
            guard success else {
                DispatchQueue.main.async { completion(nil, false) }
                return
            }
            self.queryRecentWorkout(healthStore: healthStore) { gameSession in
                DispatchQueue.main.async { completion(gameSession, true) }
            }
        }
    }

    private func queryRecentWorkout(
        healthStore: HKHealthStore,
        completion: @escaping (GameSession?) -> Void
    ) {
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .pickleball)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: workoutPredicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, results, _ in
            guard let self else { return }
            guard let workout = results?.first as? HKWorkout else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let samplePredicate = HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate,
                options: .strictStartDate
            )

            let hrQuery = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: samplePredicate,
                options: .discreteAverage
            ) { _, hrStats, _ in
                let avgHR = hrStats?
                    .averageQuantity()?
                    .doubleValue(for: HKUnit(from: "count/min")) ?? 0

                let energyQuery = HKStatisticsQuery(
                    quantityType: HKQuantityType(.activeEnergyBurned),
                    quantitySamplePredicate: samplePredicate,
                    options: .cumulativeSum
                ) { _, energyStats, _ in
                    let calories = energyStats?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie()) ?? 0

                    let gameSession = GameSession(
                        matchID: nil,
                        date: workout.startDate,
                        duration: workout.duration,
                        totalShots: 0,
                        forehandCount: 0,
                        backhandCount: 0,
                        volleyCount: 0,
                        serveCount: 0,
                        maxRallyLength: 0,
                        avgHeartRate: avgHR,
                        caloriesBurned: calories,
                        fatigueOnset: 0
                    )
                    DispatchQueue.main.async {
                        self.recentGame = gameSession
                        completion(gameSession)
                    }
                }
                healthStore.execute(energyQuery)
            }
            healthStore.execute(hrQuery)
        }
        healthStore.execute(query)
    }

    // MARK: - Wake Watch App ───────────────────────────────────

    func wakeWatchForMatch() {
        guard let session, session.isReachable else { return }

        let payload: [String: Any] = [
            "command": "startMatchAnalytics",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(payload, replyHandler: nil) { error in
            print("Watch wake failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Game History Persistence ─────────────────────────
    // All history I/O runs on ioQueue. Public-ish methods hop the queue
    // themselves; internal helpers assume they're already on it.

    private func saveGame(_ session: GameSession) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            var history = self.loadHistoryOnQueue()
            history.append(session)
            if history.count > 50 { history.removeFirst() }
            self.persistHistoryOnQueue(history)
        }
    }

    /// Caller must already be on ioQueue.
    private func loadHistoryOnQueue() -> [GameSession] {
        guard let data = UserDefaults.standard.data(forKey: "gameHistory") else {
            return []
        }
        do {
            return try JSONDecoder().decode([GameSession].self, from: data)
        } catch {
            // Schema drift: preserve the bad blob so we can recover later.
            let backupKey = "gameHistory_corrupt_\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backupKey)
            UserDefaults.standard.removeObject(forKey: "gameHistory")
            return []
        }
    }

    /// Caller must already be on ioQueue.
    private func persistHistoryOnQueue(_ history: [GameSession]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "gameHistory")
        }
    }

    /// Merge final shot stats into the stub created when matchState first
    /// reported isMatchActive. Match by matchID — exact, no fuzzy timestamps.
    private func mergeShotsIntoExistingMatch(matchID: UUID, with shots: GameSession) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            var history = self.loadHistoryOnQueue()

            if let index = history.lastIndex(where: { $0.matchID == matchID }) {
                let existing = history[index]
                let merged = GameSession(
                    matchID: existing.matchID,
                    date: existing.date,
                    duration: max(existing.duration, shots.duration),
                    totalShots: shots.totalShots,
                    forehandCount: shots.forehandCount,
                    backhandCount: shots.backhandCount,
                    volleyCount: shots.volleyCount,
                    serveCount: shots.serveCount,
                    maxRallyLength: shots.maxRallyLength,
                    avgHeartRate: shots.avgHeartRate > 0 ? shots.avgHeartRate : existing.avgHeartRate,
                    caloriesBurned: shots.caloriesBurned > 0 ? shots.caloriesBurned : existing.caloriesBurned,
                    fatigueOnset: shots.fatigueOnset
                )
                history[index] = merged
                self.persistHistoryOnQueue(history)
            } else {
                history.append(shots)
                if history.count > 50 { history.removeFirst() }
                self.persistHistoryOnQueue(history)
            }
        }
    }
}

// MARK: - WCSessionDelegate ────────────────────────────────────

extension WatchConnectivityManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingPayload(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingPayload(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingPayload(userInfo)
    }

    // MARK: - Routing

    private func handleIncomingPayload(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "matchState", "watchMatchState", "phoneMatchState":
            // All three publish live state for any observing view.
            // Only watch-originated states create history stubs.
            if let state = MatchState(message: message) {
                DispatchQueue.main.async { [weak self] in
                    self?.liveMatchState = state
                }
            }
            if type != "phoneMatchState" {
                handleWatchMatchState(message)
            }

        case "gameComplete":
            handleGameComplete(message)

        case "shot":
            // Live shot pings during a match — no-op. Aggregated counts
            // arrive in the final gameComplete payload.
            break

        default:
            break
        }
    }

    // MARK: - matchState handler (silent tracking)

    private func handleWatchMatchState(_ message: [String: Any]) {
        let isMatchActive = boolValue(message["isMatchActive"])
        let matchCompleted = boolValue(message["matchCompleted"])

        // matchID is required. Bail if missing.
        guard let matchIDString = message["matchID"] as? String,
              let matchID = UUID(uuidString: matchIDString) else {
            return
        }

        // Stale-pending guard: drop anything older than 4 hours.
        if let pending = pendingWatchMatch,
           Date().timeIntervalSince(pending.startDate) > 4 * 3600 {
            pendingWatchMatch = nil
        }

        // New watch match just started
        if isMatchActive,
           pendingWatchMatch?.id != matchID,
           !matchCompleted {

            let startDate = Date()
            pendingWatchMatch = PendingMatch(id: matchID, startDate: startDate)

            let stub = GameSession(
                matchID: matchID,
                date: startDate,
                duration: 0,
                totalShots: 0,
                forehandCount: 0,
                backhandCount: 0,
                volleyCount: 0,
                serveCount: 0,
                maxRallyLength: 0,
                avgHeartRate: 0,
                caloriesBurned: 0,
                fatigueOnset: 0
            )
            // saveGame hops to ioQueue internally — no main-thread bounce needed.
            saveGame(stub)
            return
        }

        // Completed or live score updates — no-op (silent tracking)
    }

    // MARK: - gameComplete handler

    private func handleGameComplete(_ message: [String: Any]) {
        let date: Date
        if let ts = (message["date"] as? NSNumber)?.doubleValue {
            date = Date(timeIntervalSince1970: ts)
        } else if let d = message["date"] as? Date {
            date = d
        } else {
            date = Date()
        }

        let matchID: UUID? = {
            guard let s = message["matchID"] as? String else { return nil }
            return UUID(uuidString: s)
        }()

        let gameSession = GameSession(
            matchID: matchID,
            date: date,
            duration: (message["duration"] as? NSNumber)?.doubleValue ?? 0,
            totalShots: intValue(message["totalShots"]),
            forehandCount: intValue(message["forehands"]),
            backhandCount: intValue(message["backhands"]),
            volleyCount: intValue(message["volleys"]),
            serveCount: intValue(message["serves"]),
            maxRallyLength: intValue(message["maxRally"]),
            avgHeartRate: (message["avgHR"] as? NSNumber)?.doubleValue ?? 0,
            caloriesBurned: (message["calories"] as? NSNumber)?.doubleValue ?? 0,
            fatigueOnset: (message["fatigueOnset"] as? NSNumber)?.doubleValue ?? 0
        )

        // @Published mutation must be on main; persistence routes itself off-main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recentGame = gameSession

            if let mid = matchID {
                self.mergeShotsIntoExistingMatch(matchID: mid, with: gameSession)
                if self.pendingWatchMatch?.id == mid {
                    self.pendingWatchMatch = nil
                }
            } else {
                self.saveGame(gameSession)
            }
        }
    }

    // MARK: - Decoding helpers

    private func intValue(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }
}

