//
//  MatchCenter.swift
//  PickleBall
//
//  Owns the match being scored right now, wherever it was started.
//
//  • Phone-started matches: the phone is the CourtKit host and holds the
//    authoritative rally log; the Watch mirrors it and sends intents.
//  • Watch-started matches: the Watch is the host; the phone mirrors,
//    records the result and can score too.
//
//  Every confirmed rally is written to SwiftData immediately, so a crash or
//  a dead battery never loses a match; interrupted matches come back as
//  "parked" and can be resumed.
//

import Foundation
import Observation
import SwiftData
import CourtKit

@MainActor
@Observable
final class LiveMatch: Identifiable {
    let setup: MatchSetup
    fileprivate(set) var replica: MatchReplica
    /// Events produced by the latest rally, for animation.
    fileprivate(set) var lastEvents: [ScoreEvent] = []
    /// Bumped on every visible change so views can animate on it.
    fileprivate(set) var revision = 0

    /// Called once when the match is completed (used by tournaments).
    @ObservationIgnored var onCompleted: ((MatchResult) -> Void)?

    fileprivate init(setup: MatchSetup, role: MatchReplica.Role, log: [Rally] = []) {
        self.setup = setup
        self.replica = MatchReplica(setup: setup, role: role, log: log)
    }

    var id: UUID { setup.matchID }
    var display: ScoreDisplay { replica.display }
    var scorer: MatchScorer { replica.scorer }
    var lineup: Lineup { setup.lineup }
    var rules: MatchRules { setup.rules }
    var sport: Sport { setup.rules.sport }
    var role: MatchReplica.Role { replica.role }
    var isFinished: Bool { replica.isFinished }
    var isEnded: Bool { replica.isEnded }
    var canUndo: Bool { replica.scorer.canUndo && !replica.isEnded }
    var isWatchHosted: Bool { setup.host == .watch }

    /// The most important pressure on the next rally, if any.
    var topPressure: (pressure: Pressure, team: Team)? {
        let options = Team.allCases.compactMap { team in scorer.pressure(for: team).map { (pressure: $0, team: team) } }
        return options.max { $0.pressure < $1.pressure }
    }

    var result: MatchResult {
        MatchResult(id: id, date: setup.startedAt, lineup: lineup, scorer: scorer)
    }
}

@MainActor
@Observable
final class MatchCenter {
    static let shared = MatchCenter()

    /// The match on screen (or on the Watch) right now.
    private(set) var live: LiveMatch?

    @ObservationIgnored private let connectivity = WatchConnectivityManager.shared
    @ObservationIgnored private let activities = LiveActivityController.shared
    private var context: ModelContext { AppDatabase.context }
    @ObservationIgnored private var didBoot = false

    private init() {}

    /// Wires connectivity and recovers matches interrupted by a crash or
    /// termination. Call once at launch.
    func boot() {
        guard !didBoot else { return }
        didBoot = true
        connectivity.onMessage = { [weak self] message in
            self?.handle(message)
        }
        recoverInterruptedMatches()
        activities.endStaleActivities()
    }

    // MARK: - Starting

    @discardableResult
    func startMatch(rules: MatchRules, lineup: Lineup, tournamentFixture: UUID? = nil) -> LiveMatch {
        if let current = live, !current.isEnded {
            park()
        }
        let setup = MatchSetup(rules: rules, lineup: lineup, host: .phone, tournamentMatchID: tournamentFixture)
        let match = LiveMatch(setup: setup, role: .host)
        context.insert(MatchRecord(setup: setup, status: .live))
        AppDatabase.save()
        PlayerDirectory.shared.adopt(lineup)

        live = match
        connectivity.send(match.replica.startMessage)
        connectivity.wakeWatchForMatch(sport: rules.sport)
        activities.start(for: match)
        Haptics.warm()
        return match
    }

    /// Resumes a parked match on the phone as its host.
    @discardableResult
    func resume(matchID: UUID) -> LiveMatch? {
        guard let record = MatchStore.shared.record(id: matchID), let stored = record.setup else { return nil }
        if let current = live, !current.isEnded, current.id != matchID {
            park()
        }
        let setup = MatchSetup(
            matchID: stored.matchID,
            rules: stored.rules,
            lineup: stored.lineup,
            startedAt: stored.startedAt,
            host: .phone,
            tournamentMatchID: stored.tournamentMatchID
        )
        record.status = .live
        record.hostRaw = DeviceRole.phone.rawValue
        AppDatabase.save()
        MatchStore.shared.reload()

        let match = LiveMatch(setup: setup, role: .host, log: record.rallyLog)
        live = match
        connectivity.send(match.replica.startMessage)
        activities.start(for: match)
        return match
    }

    // MARK: - Scoring

    func record(_ team: Team) {
        guard let match = live else { return }
        let outcome = match.replica.recordRally(wonBy: team)
        process(outcome, for: match, isLocal: true)
    }

    func undo() {
        guard let match = live, match.canUndo else { return }
        let outcome = match.replica.undo()
        process(outcome, for: match, isLocal: true)
        Haptics.soft()
    }

    /// Confirms a finished match and saves it to history.
    func finish() {
        guard let match = live else { return }
        let outcome = match.replica.end(.completed)
        process(outcome, for: match, isLocal: true)
    }

    /// Pauses the match so it can be resumed later.
    func park() {
        guard let match = live else { return }
        let outcome = match.replica.end(.parked)
        process(outcome, for: match, isLocal: true)
    }

    /// Stops without saving.
    func abandon() {
        guard let match = live else { return }
        let outcome = match.replica.end(.abandoned)
        process(outcome, for: match, isLocal: true)
    }

    /// Closes the scoreboard for a match that already ended elsewhere.
    func dismissEnded() {
        if live?.isEnded == true { live = nil }
    }

    // MARK: - Preferences for the Watch

    func publishPreferences(sport: Sport) {
        let directory = PlayerDirectory.shared
        let birthYear = Int(UserDefaults.standard.string(forKey: "profile_birthYear") ?? "")
        let currentYear = Calendar.current.component(.year, from: Date())
        let age = birthYear.map { currentYear - $0 }.flatMap { (10...100).contains($0) ? $0 : nil }
        let preferences = WatchPreferences(
            sport: sport,
            me: directory.me,
            recentPlayers: Array(directory.others.prefix(12)),
            age: age
        )
        connectivity.send(.preferences(preferences))
    }

    // MARK: - Incoming

    private func handle(_ message: SyncMessage) {
        switch message {
        case .workout(let matchID, let date, let report):
            WorkoutStore.shared.add(report, matchID: matchID, date: date)
            MatchStore.shared.reload()
            return
        case .preferences:
            return
        default:
            break
        }

        if let match = live, message.matchID == match.id {
            let outcome = match.replica.receive(message)
            process(outcome, for: match, isLocal: false)
            return
        }

        switch message {
        case .matchStarted(let snapshot), .log(let snapshot):
            adoptRemote(snapshot)
        case .matchEnded(let matchID, let reason):
            guard let record = MatchStore.shared.record(id: matchID) else { return }
            apply(reason, to: record)
        default:
            break
        }
    }

    /// A match the phone isn't showing: mirror it (Watch-started) or store it.
    private func adoptRemote(_ snapshot: LogSnapshot) {
        let setup = normalized(snapshot.setup)
        PlayerDirectory.shared.adopt(setup.lineup)
        let record = MatchStore.shared.record(id: setup.matchID) ?? {
            let record = MatchRecord(setup: setup, status: .live)
            context.insert(record)
            return record
        }()
        record.apply(log: snapshot.rallies, in: context)

        if let reason = snapshot.ended {
            apply(reason, to: record)
            return
        }
        AppDatabase.save()

        // Mirror a live Watch match if the phone is free.
        guard setup.host == .watch, live == nil || live?.isEnded == true else { return }
        let match = LiveMatch(setup: setup, role: .client, log: snapshot.rallies)
        live = match
        activities.start(for: match)
    }

    /// The device owner is the only user-kind player in an offline app. A
    /// Watch that hasn't received the owner's ID yet labels them with a
    /// Watch-local ID; map that back to the owner so the match is theirs.
    private func normalized(_ setup: MatchSetup) -> MatchSetup {
        let me = PlayerDirectory.shared.me
        var normalized = setup
        normalized.lineup.teams = setup.lineup.teams.map { roster in
            roster.map { $0.kind == .user && $0.id != me.id ? me : $0 }
        }
        return normalized
    }

    // MARK: - Processing

    private func process(_ outcome: MatchReplica.Outcome, for match: LiveMatch, isLocal: Bool) {
        if outcome.changed {
            match.lastEvents = outcome.events
            match.revision += 1
        }
        if isLocal { Haptics.play(outcome.events) }
        connectivity.send(outcome.outgoing)

        guard let record = MatchStore.shared.record(id: match.id) else { return }
        if outcome.changed {
            record.apply(log: match.replica.log, in: context)
            AppDatabase.save()
            if match.role == .host, !match.isEnded {
                connectivity.send(.log(match.replica.snapshot))
            }
            activities.update(for: match)
        }

        if let reason = match.replica.ended {
            apply(reason, to: record, match: match)
        }
    }

    private func apply(_ reason: EndReason, to record: MatchRecord, match: LiveMatch? = nil) {
        switch reason {
        case .completed where record.winner != nil:
            let alreadyCompleted = record.status == .completed
            record.status = .completed
            record.endedAt = record.endedAt ?? Date()
            AppDatabase.save()
            if let lineup = record.lineup { PlayerDirectory.shared.markPlayed(lineup) }
            if !alreadyCompleted, let match { match.onCompleted?(match.result) }
        case .completed, .parked:
            record.status = .parked
            AppDatabase.save()
        case .abandoned:
            context.delete(record)
            AppDatabase.save()
        }
        MatchStore.shared.reload()

        if let match, live?.id == match.id {
            activities.end(for: match, dismissImmediately: reason != .completed)
            // A completed match keeps its result card up until dismissed.
            if reason != .completed { live = nil }
        }
    }

    private func recoverInterruptedMatches() {
        let liveRaw = MatchStatus.live.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.statusRaw == liveRaw })
        let staleCutoff = Date().addingTimeInterval(-6 * 3600)
        for record in (try? context.fetch(descriptor)) ?? [] {
            let isWatchHosted = record.hostRaw == DeviceRole.watch.rawValue
            if isWatchHosted && record.startedAt > staleCutoff { continue }
            record.status = record.winner != nil ? .completed : .parked
            if record.status == .completed { record.endedAt = record.endedAt ?? Date() }
        }
        AppDatabase.save()
        MatchStore.shared.reload()
    }
}
