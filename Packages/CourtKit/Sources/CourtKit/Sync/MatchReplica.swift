//
//  MatchReplica.swift
//  CourtKit
//
//  One device's copy of a live match. Pure state machine: feed it local taps
//  and incoming messages, send whatever it returns in `outgoing`. The
//  transport (WatchConnectivity) and the UI stay outside.
//
//  Host: owns `log`. Local taps are applied and broadcast as events. Client
//  intents are applied only when their `basedOn` equals the host log length;
//  otherwise they are rejected and the client receives the full log.
//
//  Client: keeps the host-confirmed `log` plus `pending` intents it has sent
//  but the host has not yet acknowledged. What the UI shows is the log with
//  pending intents applied on top, so taps feel instant even over a slow or
//  queued link. Rejections and snapshots reconcile back to the host's truth.
//

import Foundation

public struct MatchReplica: Equatable, Sendable {
    public enum Role: String, Hashable, Sendable {
        case host
        case client
    }

    /// What a mutation produced.
    public struct Outcome: Equatable, Sendable {
        /// Score events for the local UI (haptics, animation).
        public var events: [ScoreEvent] = []
        /// Messages to send to the other device, in order.
        public var outgoing: [SyncMessage] = []
        /// Whether the visible score changed.
        public var changed: Bool = false

        public init(events: [ScoreEvent] = [], outgoing: [SyncMessage] = [], changed: Bool = false) {
            self.events = events
            self.outgoing = outgoing
            self.changed = changed
        }
    }

    public let setup: MatchSetup
    public let role: Role
    public private(set) var log: [Rally]
    public private(set) var pending: [RallyIntent]
    public private(set) var ended: EndReason?
    /// The optimistic view: `log` with `pending` applied.
    public private(set) var scorer: MatchScorer

    /// Host only: intents already applied, to drop duplicate deliveries.
    private var appliedIntentIDs: [UUID]
    /// Client only: a log request is outstanding. The host republishes its
    /// log on every change, so one request is enough.
    private var awaitingLog = false
    private static let appliedIntentMemory = 64

    public init(setup: MatchSetup, role: Role, log: [Rally] = [], ended: EndReason? = nil) {
        self.setup = setup
        self.role = role
        self.log = log
        self.pending = []
        self.ended = ended
        self.appliedIntentIDs = []
        self.scorer = MatchScorer(rules: setup.rules, rallies: log)
        // Drop any rallies past the end of the match.
        self.log = scorer.rallies
    }

    public var matchID: UUID { setup.matchID }
    public var display: ScoreDisplay { scorer.display }
    public var isFinished: Bool { scorer.isFinished }
    public var isEnded: Bool { ended != nil }

    public var snapshot: LogSnapshot {
        LogSnapshot(setup: setup, rallies: log, appliedIntentIDs: appliedIntentIDs, ended: ended)
    }

    /// Message a host sends when the match begins (or is resumed).
    public var startMessage: SyncMessage { .matchStarted(snapshot) }

    // MARK: - Local actions

    public mutating func recordRally(wonBy team: Team, at date: Date = Date()) -> Outcome {
        guard ended == nil, !scorer.isFinished else { return Outcome() }
        switch role {
        case .host:
            return hostAppend(Rally(winner: team, at: date), intentID: nil)
        case .client:
            let intent = RallyIntent(kind: .rally(team, at: date), basedOn: scorer.rallies.count)
            pending.append(intent)
            let events = scorer.recordRally(wonBy: team, at: date)
            return Outcome(events: events, outgoing: [.intent(matchID: matchID, intent)], changed: true)
        }
    }

    public mutating func undo() -> Outcome {
        guard ended == nil, scorer.canUndo else { return Outcome() }
        switch role {
        case .host:
            return hostUndo(intentID: nil)
        case .client:
            let sequence = scorer.rallies.count
            let intent = RallyIntent(kind: .undo(sequence: sequence), basedOn: sequence)
            pending.append(intent)
            scorer.undo()
            return Outcome(outgoing: [.intent(matchID: matchID, intent)], changed: true)
        }
    }

    /// Ends the match on this device and tells the other one.
    public mutating func end(_ reason: EndReason) -> Outcome {
        guard ended == nil else { return Outcome() }
        ended = reason
        pending.removeAll()
        rebuild()
        return Outcome(outgoing: [.matchEnded(matchID: matchID, reason), .log(snapshot)], changed: true)
    }

    // MARK: - Incoming

    public mutating func receive(_ message: SyncMessage) -> Outcome {
        guard message.matchID == matchID else { return Outcome() }
        switch (role, message) {
        case (.host, .intent(_, let intent)):
            return hostReceive(intent)
        case (.host, .logRequest):
            return Outcome(outgoing: [.log(snapshot)])
        case (.client, .event(_, let event)):
            return clientReceive(event)
        case (.client, .intentRejected(_, let intentID)):
            guard let index = pending.firstIndex(where: { $0.id == intentID }) else { return Outcome() }
            // Everything after the rejected intent was built on top of it.
            pending.removeSubrange(index...)
            return rebuild()
        case (.client, .log(let snapshot)), (.client, .matchStarted(let snapshot)):
            return clientAdopt(snapshot)
        case (_, .matchEnded(_, let reason)):
            guard ended == nil else { return Outcome() }
            ended = reason
            pending.removeAll()
            var outcome = rebuild()
            outcome.changed = true
            return outcome
        default:
            return Outcome()
        }
    }

    // MARK: - Host

    private mutating func hostAppend(_ rally: Rally, intentID: UUID?) -> Outcome {
        log.append(rally)
        let events = scorer.recordRally(wonBy: rally.winner, at: rally.at)
        if let intentID { remember(intentID) }
        let event = RallyEvent(sequence: log.count, kind: .rally(rally.winner, at: rally.at), intentID: intentID)
        return Outcome(events: events, outgoing: [.event(matchID: matchID, event)], changed: true)
    }

    private mutating func hostUndo(intentID: UUID?) -> Outcome {
        guard !log.isEmpty else { return Outcome() }
        let sequence = log.count
        log.removeLast()
        scorer.undo()
        if let intentID { remember(intentID) }
        let event = RallyEvent(sequence: sequence, kind: .undo, intentID: intentID)
        return Outcome(outgoing: [.event(matchID: matchID, event)], changed: true)
    }

    private mutating func hostReceive(_ intent: RallyIntent) -> Outcome {
        if appliedIntentIDs.contains(intent.id) { return Outcome() }
        guard ended == nil, intent.basedOn == log.count else {
            return Outcome(outgoing: [.intentRejected(matchID: matchID, intentID: intent.id), .log(snapshot)])
        }
        switch intent.kind {
        case .rally(let team, let at):
            guard !scorer.isFinished else {
                return Outcome(outgoing: [.intentRejected(matchID: matchID, intentID: intent.id), .log(snapshot)])
            }
            return hostAppend(Rally(winner: team, at: at), intentID: intent.id)
        case .undo(let sequence):
            guard sequence == log.count, sequence > 0 else {
                return Outcome(outgoing: [.intentRejected(matchID: matchID, intentID: intent.id), .log(snapshot)])
            }
            return hostUndo(intentID: intent.id)
        }
    }

    private mutating func remember(_ intentID: UUID) {
        appliedIntentIDs.append(intentID)
        if appliedIntentIDs.count > Self.appliedIntentMemory {
            appliedIntentIDs.removeFirst(appliedIntentIDs.count - Self.appliedIntentMemory)
        }
    }

    // MARK: - Client

    private mutating func clientReceive(_ event: RallyEvent) -> Outcome {
        switch event.kind {
        case .rally(let team, let at):
            if event.sequence <= log.count { return Outcome() }          // duplicate
            guard event.sequence == log.count + 1 else {                 // gap
                return requestLog()
            }
            log.append(Rally(winner: team, at: at))
        case .undo:
            guard event.sequence == log.count else {
                return event.sequence > log.count ? requestLog() : Outcome()
            }
            log.removeLast()
        }

        let isOwnIntent = event.intentID != nil && pending.first?.id == event.intentID
        if isOwnIntent {
            pending.removeFirst()
            // Our tap was already on screen; nothing visible changes.
            let previous = scorer
            rebuild()
            return Outcome(changed: previous != scorer)
        }
        return rebuild(reportEventsFor: event)
    }

    private mutating func requestLog() -> Outcome {
        guard !awaitingLog else { return Outcome() }
        awaitingLog = true
        return Outcome(outgoing: [.logRequest(matchID: matchID)])
    }

    private mutating func clientAdopt(_ snapshot: LogSnapshot) -> Outcome {
        awaitingLog = false
        let acknowledged = Set(snapshot.appliedIntentIDs)
        log = snapshot.rallies
        pending.removeAll { acknowledged.contains($0.id) }
        // Surviving intents only make sense if they still sit on the host log.
        if let first = pending.first, first.basedOn != log.count {
            pending.removeAll()
        }
        if let reason = snapshot.ended {
            ended = reason
            pending.removeAll()
        }
        return rebuild()
    }

    /// Recomputes the optimistic view from `log` and `pending`.
    @discardableResult
    private mutating func rebuild(reportEventsFor event: RallyEvent? = nil) -> Outcome {
        let before = scorer
        var view = log
        for intent in pending {
            switch intent.kind {
            case .rally(let team, let at): view.append(Rally(winner: team, at: at))
            case .undo: if !view.isEmpty { view.removeLast() }
            }
        }
        scorer = MatchScorer(rules: setup.rules, rallies: view)

        var events: [ScoreEvent] = []
        if let event, case .rally(let team, _) = event.kind, scorer.rallies.count == before.rallies.count + 1 {
            events = MatchScorer.events(from: before.display, to: scorer.display, rallyWinner: team)
        }
        return Outcome(events: events, changed: before != scorer)
    }
}
