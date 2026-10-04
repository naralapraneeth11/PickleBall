//
//  WatchConnectivityManager.swift
//  PickleBall
//
//  Phone side of the Watch link. Single owner of WCSession.delegate on iOS.
//  Speaks only CourtKit `SyncMessage`s: rally events and intents, never
//  score snapshots.
//
//  Delivery policy
//  • Events, intents, rejections, workouts: `sendMessage` when the Watch is
//    reachable (instant), otherwise `transferUserInfo` (queued, FIFO,
//    survives app restarts). Receivers are idempotent, so a message that
//    arrives by both routes is harmless.
//  • Match logs and preferences: application context, one slot each, so the
//    Watch can always bootstrap from the latest state.
//  • Watch-owned matches (journal schema 2): batches of operations,
//    receipts, drafts and grants. Sent immediately when reachable, else as
//    one queued batch that replaces the previous one. Receivers save before
//    they acknowledge, so retries are always safe.
//

import Foundation
import Combine
import WatchConnectivity
import HealthKit
import CourtKit

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isWatchReachable = false

    /// Receives every decoded message on the main actor.
    var onMessage: ((SyncMessage) -> Void)?
    /// Receives journal (schema 2) messages on the main actor.
    var onJournal: (([JournalMessage]) -> Void)?
    /// The Watch became reachable (or the session activated): resend.
    var onBecameAvailable: (() -> Void)?

    /// What the app can honestly say about the Watch right now.
    enum Availability: Equatable {
        case checking
        case unsupported
        case notPaired
        case appNotInstalled
        /// Installed, but messages can't be delivered immediately.
        case notReachable
        case reachable
    }

    var availability: Availability {
        guard let session else { return .unsupported }
        guard session.activationState == .activated else { return .checking }
        if !isWatchPaired { return .notPaired }
        if !isWatchAppInstalled { return .appNotInstalled }
        return isWatchReachable ? .reachable : .notReachable
    }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var contextSlots: [String: Data] = [:]
    /// Messages sent before the session finished activating.
    private var pendingMessages: [SyncMessage] = []
    private let healthStore = HKHealthStore()

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Sending

    func send(_ messages: [SyncMessage]) {
        for message in messages { send(message) }
    }

    func send(_ message: SyncMessage) {
        guard let session else { return }

        if let key = message.contextKey, let data = message.encoded {
            contextSlots[key] = data
        }
        guard session.activationState == .activated else {
            if message.contextKey == nil { pendingMessages.append(message) }
            return
        }
        // No Watch app to talk to: nothing to send (the context stays cached).
        guard session.isPaired, session.isWatchAppInstalled else { return }

        if message.contextKey != nil {
            do {
                try session.updateApplicationContext(contextSlots)
            } catch {
                print("WatchConnectivity: updateApplicationContext failed: \(error.localizedDescription)")
            }
            // Snapshots also go out immediately when the Watch is awake.
            if case .matchStarted = message, session.isReachable {
                session.sendMessage(message.wcPayload, replyHandler: nil, errorHandler: nil)
            }
            return
        }

        let payload = message.wcPayload
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                print("WatchConnectivity: sendMessage failed (\(error.localizedDescription)); queueing")
                Task { @MainActor in self?.queue(message) }
            }
        } else {
            queue(message)
        }
    }

    private func queue(_ message: SyncMessage) {
        session?.transferUserInfo(message.wcPayload)
    }

    /// Sends journal messages as one batch.
    func sendJournal(_ messages: [JournalMessage]) {
        guard !messages.isEmpty, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let payload = JournalMessage.batchPayload(messages)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.queueJournal(payload) }
            }
        } else {
            queueJournal(payload)
        }
    }

    private func queueJournal(_ payload: [String: Any]) {
        guard let session else { return }
        session.transferUserInfo(payload)
    }

    // MARK: - Health

    /// Asks for Health read access (workouts, heart rate, energy).
    func requestHealthAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        healthStore.requestAuthorization(toShare: [], read: types) { success, _ in
            Task { @MainActor in completion(success) }
        }
    }

    /// Launches the Watch app into a workout so heart rate is recorded from
    /// the first rally, even if the app wasn't open on the wrist.
    func wakeWatchForMatch(sport: Sport) {
        guard isWatchPaired, isWatchAppInstalled else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sport == .pickleball ? .pickleball : .paddleSports
        configuration.locationType = .outdoor
        healthStore.startWatchApp(with: configuration) { success, error in
            if !success, let error {
                print("WatchConnectivity: startWatchApp failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receiving

    fileprivate func deliver(_ messages: [SyncMessage]) {
        for message in messages { onMessage?(message) }
    }

    fileprivate func deliver(journal messages: [JournalMessage]) {
        guard !messages.isEmpty else { return }
        onJournal?(messages)
    }

    /// Pushes everything that was sent before activation completed.
    fileprivate func flushPending() {
        guard let session, session.activationState == .activated else { return }
        if !contextSlots.isEmpty {
            try? session.updateApplicationContext(contextSlots)
        }
        let queued = pendingMessages
        pendingMessages.removeAll()
        send(queued)
    }

    fileprivate func refreshState() {
        guard let session else { return }
        let wasReachable = isWatchReachable
        isWatchPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isWatchReachable = session.isReachable
        if isWatchReachable, !wasReachable { onBecameAvailable?() }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WatchConnectivity: activation failed: \(error.localizedDescription)")
        }
        let pending = SyncMessage.messages(in: session.receivedApplicationContext)
        Task { @MainActor in
            self.refreshState()
            self.flushPending()
            self.deliver(pending)
            self.onBecameAvailable?()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let messages = SyncMessage.messages(in: message)
        let journal = JournalMessage.messages(in: message)
        Task { @MainActor in
            self.deliver(messages)
            self.deliver(journal: journal)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let messages = SyncMessage.messages(in: applicationContext)
        Task { @MainActor in self.deliver(messages) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let messages = SyncMessage.messages(in: userInfo)
        let journal = JournalMessage.messages(in: userInfo)
        Task { @MainActor in
            self.deliver(messages)
            self.deliver(journal: journal)
        }
    }
}
