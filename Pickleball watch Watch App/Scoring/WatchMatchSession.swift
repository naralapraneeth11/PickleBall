//
//  WatchMatchSession.swift
//  Pickleball watch Watch App
//
//  The Watch's side of a match. Watch-started matches are hosted here (the
//  Watch owns the rally log); phone-started matches are mirrored as a
//  client. Either way the Watch sends rally events or intents, never
//  score snapshots, and replays the log through the same CourtKit engine
//  as the phone.
//

import Foundation
import Observation
import WatchConnectivity
import WatchKit
import CourtKit

@MainActor
@Observable
final class WatchMatchSession: NSObject {
    static let shared = WatchMatchSession()

    private(set) var replica: MatchReplica? = nil
    private(set) var preferences: WatchPreferences
    /// The sport shown on the idle screen. Follows the phone, but the crown
    /// switcher can change it locally.
    var sport: Sport
    private(set) var revision = 0
    private(set) var lastEvents: [ScoreEvent] = []
    private(set) var isPhoneReachable = false
    /// The latest crowd tap that buzzed the wrist: "Priya · Let's go!".
    private(set) var cheer: String?
    @ObservationIgnored private var chantPlayer = ChantPlayer()
    @ObservationIgnored private var cheerTask: Task<Void, Never>?

    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var contextSlots: [String: Data] = [:]
    @ObservationIgnored private var pendingMessages: [SyncMessage] = []
    /// Matches finished here as the client that the phone hasn't confirmed
    /// yet. Kept across relaunches and resent until the phone answers.
    private var unsentEnds: [UUID: MatchReplica] = [:]

    /// Finished matches still on their way to the iPhone.
    var unsentCount: Int { unsentEnds.count }

    private enum Keys {
        static let preferences = "watch.preferences"
        static let hostedMatch = "watch.hostedMatch"
        static let unsentEnds = "watch.unsentEnds"
        static let localPlayerID = "watch.localPlayerID"
        static let anonymousIDs = "watch.anonymousPlayerIDs"
    }

    private override init() {
        let stored = UserDefaults.standard.data(forKey: Keys.preferences)
            .flatMap { try? JSONDecoder().decode(WatchPreferences.self, from: $0) }
        let preferences = stored ?? WatchPreferences(sport: .pickleball, me: nil)
        self.preferences = preferences
        self.sport = preferences.sport
        super.init()
        restoreHostedMatch()
        restoreUnsentEnds()
        session?.delegate = self
        session?.activate()
    }

    // MARK: - State

    var match: MatchReplica? { replica }
    var display: ScoreDisplay? { replica?.display }
    var isLive: Bool { replica.map { !$0.isEnded } ?? false }
    var isFinished: Bool { replica?.isFinished ?? false }
    var canUndo: Bool { replica.map { $0.scorer.canUndo && !$0.isEnded } ?? false }

    /// The device owner, or a stable Watch-local "You" until the phone syncs.
    var me: PlayerRef {
        if let me = preferences.me { return me }
        return PlayerRef(id: stableID(Keys.localPlayerID), kind: .user, displayName: "You")
    }

    var recentPlayers: [PlayerRef] { preferences.recentPlayers }

    /// A stable guest used when no opponent is picked, so anonymous matches
    /// don't create a new player every time.
    func anonymousPlayer(_ label: String) -> PlayerRef {
        var ids = (defaults.dictionary(forKey: Keys.anonymousIDs) as? [String: String]) ?? [:]
        let id = ids[label].flatMap(UUID.init(uuidString:)) ?? UUID()
        ids[label] = id.uuidString
        defaults.set(ids, forKey: Keys.anonymousIDs)
        return PlayerRef(id: PlayerID(rawValue: id), kind: .guest, displayName: label)
    }

    private func stableID(_ key: String) -> PlayerID {
        if let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) {
            return PlayerID(rawValue: id)
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return PlayerID(rawValue: id)
    }

    // MARK: - Actions

    /// Starts a match hosted by the Watch.
    func startMatch(rules: MatchRules, lineup: Lineup) {
        let setup = MatchSetup(rules: rules, lineup: lineup, host: .watch)
        let replica = MatchReplica(setup: setup, role: .host)
        self.replica = replica
        lastEvents = []
        revision += 1
        send(replica.startMessage)
        persistHostedMatch()
        WorkoutManager.shared.start(sport: rules.sport, matchID: setup.matchID)
    }

    func record(_ team: Team) {
        guard var replica, !replica.isEnded else { return }
        let outcome = replica.recordRally(wonBy: team)
        self.replica = replica
        apply(outcome, isLocal: true)
    }

    func undo() {
        guard var replica, canUndo else { return }
        let outcome = replica.undo()
        self.replica = replica
        apply(outcome, isLocal: true)
        Haptics.soft()
    }

    /// Confirms a finished match; the phone saves it to history.
    func finish() {
        end(.completed)
    }

    func abandon() {
        end(.abandoned)
    }

    /// Clears a match that has ended (on either device).
    func dismissEnded() {
        guard replica?.isEnded == true else { return }
        replica = nil
        revision += 1
        defaults.removeObject(forKey: Keys.hostedMatch)
    }

    private func end(_ reason: EndReason) {
        guard var replica else { return }
        let outcome = replica.end(reason)
        self.replica = replica
        apply(outcome, isLocal: true)
    }

    // MARK: - Processing

    private func apply(_ outcome: MatchReplica.Outcome, isLocal: Bool) {
        guard let replica else { return }
        if outcome.changed {
            lastEvents = outcome.events
            revision += 1
        }
        if isLocal || !outcome.events.isEmpty {
            Haptics.play(outcome.events)
        }
        for message in outcome.outgoing { send(message) }
        if replica.role == .host, outcome.changed, !replica.isEnded {
            send(.log(replica.snapshot))
        }
        persistHostedMatch()

        trackUnsentEnd(replica)

        if let reason = replica.ended {
            let report = WorkoutManager.shared.stop()
            if reason != .abandoned, let report {
                send(.workout(matchID: replica.matchID, date: replica.setup.startedAt, report))
            }
            if reason != .completed {
                // Parked or abandoned elsewhere: nothing to show.
                dismissEnded()
            }
        }
    }

    private func handle(_ message: SyncMessage) {
        switch message {
        case .preferences(let preferences):
            let sportChanged = preferences.sport != self.preferences.sport
            self.preferences = preferences
            if sportChanged { sport = preferences.sport }
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: Keys.preferences)
            }
            return
        case .workout:
            return
        case .crowd(let tap, let chant):
            play(tap, chant: chant)
            return
        default:
            break
        }

        if var replica, message.matchID == replica.matchID {
            let outcome = replica.receive(message)
            self.replica = replica
            apply(outcome, isLocal: false)
            return
        }

        // The phone answering a match finished here earlier.
        if let matchID = message.matchID, var stored = unsentEnds[matchID] {
            let outcome = stored.receive(message)
            for reply in outcome.outgoing { send(reply) }
            trackUnsentEnd(stored)
            return
        }

        // A phone-started match the Watch isn't showing yet: mirror it.
        switch message {
        case .matchStarted(let snapshot), .log(let snapshot):
            guard snapshot.setup.host == .phone, snapshot.ended == nil else { return }
            if let current = replica, !current.isEnded { return }
            let mirrored = MatchReplica(mirroring: snapshot)
            replica = mirrored
            lastEvents = []
            revision += 1
            sport = snapshot.setup.rules.sport
            WorkoutManager.shared.start(sport: snapshot.setup.rules.sport, matchID: snapshot.setup.matchID)
        default:
            break
        }
    }

    // MARK: - Crowd taps

    /// Plays a friend's chant on the wrist — at most one every few seconds,
    /// and never for a match that isn't on.
    private func play(_ tap: CrowdTap, chant: Chant) {
        guard let replica, replica.matchID == tap.matchID, !replica.isEnded,
              chantPlayer.shouldPlay(tap, now: Date()) else { return }
        let first = tap.fromName.split(separator: " ").first.map(String.init) ?? tap.fromName
        cheer = "\(first) · \(chant.name)"
        cheerTask?.cancel()
        cheerTask = Task { [weak self] in
            var elapsed = 0.0
            for beat in chant.beats {
                let wait = beat.at - elapsed
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                elapsed = beat.at
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(beat.strength >= 0.85 ? .start : beat.strength >= 0.5 ? .directionUp : .click)
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.cheer = nil
        }
    }

    // MARK: - Transport

    private func send(_ message: SyncMessage) {
        guard let session else { return }
        if let key = message.contextKey, let data = message.encoded {
            contextSlots[key] = data
        }
        guard session.activationState == .activated else {
            if message.contextKey == nil { pendingMessages.append(message) }
            return
        }
        if message.contextKey != nil {
            try? session.updateApplicationContext(contextSlots)
            if case .matchStarted = message, session.isReachable {
                session.sendMessage(message.wcPayload, replyHandler: nil, errorHandler: nil)
            }
            return
        }
        let payload = message.wcPayload
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.session?.transferUserInfo(payload) }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    fileprivate func deliver(_ messages: [SyncMessage]) {
        for message in messages { handle(message) }
    }

    fileprivate func flushPending() {
        guard let session, session.activationState == .activated else { return }
        if !contextSlots.isEmpty { try? session.updateApplicationContext(contextSlots) }
        let queued = pendingMessages
        pendingMessages.removeAll()
        for message in queued { send(message) }
        resendUnsentEnds()
    }

    fileprivate func refreshReachability() {
        let wasReachable = isPhoneReachable
        isPhoneReachable = session?.isReachable ?? false
        if isPhoneReachable, !wasReachable { resendUnsentEnds() }
    }

    // MARK: - Finishes the phone hasn't confirmed

    private func trackUnsentEnd(_ replica: MatchReplica) {
        let before = unsentEnds[replica.matchID] != nil
        if replica.isAwaitingEndAck {
            unsentEnds[replica.matchID] = replica
        } else {
            unsentEnds[replica.matchID] = nil
        }
        if before || replica.isAwaitingEndAck { persistUnsentEnds() }
    }

    private func resendUnsentEnds() {
        for replica in unsentEnds.values {
            if let request = replica.pendingEndRequest { send(request) }
        }
    }

    private func persistUnsentEnds() {
        if unsentEnds.isEmpty {
            defaults.removeObject(forKey: Keys.unsentEnds)
        } else if let data = try? JSONEncoder().encode(Array(unsentEnds.values)) {
            defaults.set(data, forKey: Keys.unsentEnds)
        }
    }

    private func restoreUnsentEnds() {
        guard let data = defaults.data(forKey: Keys.unsentEnds),
              let list = try? JSONDecoder().decode([MatchReplica].self, from: data) else { return }
        // A day is plenty: after that the phone has long since settled it.
        for replica in list where Date().timeIntervalSince(replica.setup.startedAt) < 24 * 3600 {
            unsentEnds[replica.matchID] = replica
        }
    }

    // MARK: - Crash recovery for Watch-hosted matches

    private func persistHostedMatch() {
        guard let replica, replica.role == .host, !replica.isEnded else {
            defaults.removeObject(forKey: Keys.hostedMatch)
            return
        }
        if let data = try? JSONEncoder().encode(replica.snapshot) {
            defaults.set(data, forKey: Keys.hostedMatch)
        }
    }

    private func restoreHostedMatch() {
        guard let data = defaults.data(forKey: Keys.hostedMatch),
              let snapshot = try? JSONDecoder().decode(LogSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.setup.startedAt) < 6 * 3600 else {
            defaults.removeObject(forKey: Keys.hostedMatch)
            return
        }
        replica = MatchReplica(setup: snapshot.setup, role: .host, log: snapshot.rallies)
        sport = snapshot.setup.rules.sport
    }
}

// MARK: - WCSessionDelegate

extension WatchMatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let pending = SyncMessage.messages(in: session.receivedApplicationContext)
        Task { @MainActor in
            self.refreshReachability()
            self.flushPending()
            self.deliver(pending)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshReachability() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let messages = SyncMessage.messages(in: message)
        Task { @MainActor in self.deliver(messages) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let messages = SyncMessage.messages(in: applicationContext)
        Task { @MainActor in self.deliver(messages) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let messages = SyncMessage.messages(in: userInfo)
        Task { @MainActor in self.deliver(messages) }
    }
}
