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
import CourtNet

@MainActor
@Observable
final class LiveMatch: Identifiable {
    let setup: MatchSetup
    fileprivate(set) var replica: MatchReplica
    /// Events produced by the latest rally, for animation.
    fileprivate(set) var lastEvents: [ScoreEvent] = []
    /// Bumped on every visible change so views can animate on it.
    fileprivate(set) var revision = 0

    /// Called once when the match is completed.
    @ObservationIgnored var onCompleted: ((MatchResult) -> Void)?

    /// Squad, tournament fixture, call out and court the match belongs to.
    fileprivate(set) var context: MatchContext
    /// Friends cheering: rises with every crowd tap and fades.
    fileprivate(set) var crowd = CrowdMeter()
    fileprivate(set) var lastTap: CrowdTap?
    /// Set at a changeover when a photo would be welcome.
    var photoPromptVisible = false
    @ObservationIgnored fileprivate var photoPrompter = PhotoPrompter()

    fileprivate init(setup: MatchSetup, role: MatchReplica.Role, log: [Rally] = [], context: MatchContext = MatchContext(),
                     revision: Revision? = nil) {
        self.setup = setup
        self.replica = MatchReplica(setup: setup, role: role, log: log, revision: revision)
        self.context = context
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
    /// Scored on the Watch from its durable journal: the phone shows it and
    /// never adds to it.
    fileprivate(set) var isWatchOwned = false

    /// The most important pressure on the next rally, if any.
    var topPressure: (pressure: Pressure, team: Team)? {
        let options = Team.allCases.compactMap { team in scorer.pressure(for: team).map { (pressure: $0, team: team) } }
        return options.max { $0.pressure < $1.pressure }
    }

    var result: MatchResult {
        var result = MatchResult(id: id, date: setup.startedAt, lineup: lineup, scorer: scorer)
        result.squadID = context.squadID
        return result
    }

    /// The story of the match so far.
    var drama: DramaReport {
        DramaDetector.analyze(rules: rules, rallies: replica.log)
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

    /// The phone's copy of Watch-owned matches (CourtKit journal), saved
    /// before anything is acknowledged to the Watch.
    @ObservationIgnored private var journal: MatchCoordinator?
    /// A match set up here and handed to the Watch.
    private(set) var handoff: WatchHandoff?
    /// The Watch runs a newer protocol than this app.
    private(set) var watchNeedsUpdate = false

    private init() {}

    /// Wires connectivity and recovers matches interrupted by a crash or
    /// termination. Call once at launch.
    func boot() {
        guard !didBoot else { return }
        didBoot = true
        connectivity.onMessage = { [weak self] message in
            self?.handle(message)
        }
        connectivity.onJournal = { [weak self] messages in
            self?.handleJournal(messages)
        }
        connectivity.onBecameAvailable = { [weak self] in
            self?.resendHandoff()
        }
        openJournal()
        recoverInterruptedMatches()
        activities.endStaleActivities()
    }

    // MARK: - Starting

    @discardableResult
    func startMatch(rules: MatchRules, lineup: Lineup, context matchContext: MatchContext = MatchContext()) -> LiveMatch {
        if let current = live, !current.isEnded {
            park()
        }
        var matchContext = matchContext
        if matchContext.squadID == nil {
            matchContext.squadID = Social.shared.sharedSquad(for: lineup.allPlayers.map(\.id))?.id
        }
        let setup = MatchSetup(rules: rules, lineup: lineup, host: .phone, tournamentMatchID: matchContext.fixtureID)
        let match = LiveMatch(setup: setup, role: .host, context: matchContext)
        let record = MatchRecord(setup: setup, status: .live)
        record.matchContext = matchContext
        context.insert(record)
        AppDatabase.save()
        PlayerDirectory.shared.adopt(lineup)

        live = match
        connectivity.send(match.replica.startMessage)
        connectivity.wakeWatchForMatch(sport: rules.sport)
        activities.start(for: match)
        Social.shared.goLive(match)
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

        let match = LiveMatch(setup: setup, role: .host, log: record.rallyLog, context: record.matchContext)
        live = match
        connectivity.send(match.replica.startMessage)
        activities.start(for: match)
        Social.shared.goLive(match)
        return match
    }

    // MARK: - Scoring

    func record(_ team: Team) {
        guard let match = live else { return }
        guard !match.isWatchOwned else { return scoringIsOnWatch() }
        let outcome = match.replica.recordRally(wonBy: team)
        process(outcome, for: match, isLocal: true)
    }

    func undo() {
        guard let match = live, match.canUndo else { return }
        guard !match.isWatchOwned else { return scoringIsOnWatch() }
        let outcome = match.replica.undo()
        process(outcome, for: match, isLocal: true)
        Haptics.soft()
    }

    /// Confirms a finished match and saves it to history.
    func finish() {
        guard let match = live else { return }
        guard !match.isWatchOwned else { return scoringIsOnWatch() }
        let outcome = match.replica.end(.completed)
        process(outcome, for: match, isLocal: true)
    }

    /// Pauses the match so it can be resumed later.
    func park() {
        guard let match = live else { return }
        // A Watch-owned match keeps going on the wrist; just close it here.
        if match.isWatchOwned { live = nil; return }
        let outcome = match.replica.end(.parked)
        process(outcome, for: match, isLocal: true)
    }

    /// Stops without saving.
    func abandon() {
        guard let match = live else { return }
        guard !match.isWatchOwned else { return scoringIsOnWatch() }
        let outcome = match.replica.end(.abandoned)
        process(outcome, for: match, isLocal: true)
    }

    /// Closes the scoreboard for a match that already ended elsewhere.
    func dismissEnded() {
        if live?.isEnded == true || live?.isWatchOwned == true { live = nil }
    }

    private func scoringIsOnWatch() {
        Haptics.warning()
        Social.shared.notice = String(localized: "This match is scored on your Apple Watch.")
    }

    // MARK: - Crowd and photos

    /// A friend's crowd tap: fills the meter and buzzes the Watch.
    func receiveCrowd(_ tap: CrowdTap, chant: Chant) {
        guard let match = live, match.id == tap.matchID, !match.isEnded else { return }
        match.crowd.add(at: Date())
        match.lastTap = tap
        connectivity.send(.crowd(tap, chant))
    }

    /// Photos taken at changeovers, stored until the Replay is posted.
    static func photoDirectory(for matchID: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatchPhotos/\(matchID.uuidString)", isDirectory: true)
    }

    func savePhoto(_ data: Data, for matchID: UUID) {
        let directory = Self.photoDirectory(for: matchID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let count = (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
        try? data.write(to: directory.appendingPathComponent("\(count + 1).jpg"), options: .atomic)
        live?.photoPromptVisible = false
    }

    static func photos(for matchID: UUID) -> [URL] {
        let directory = photoDirectory(for: matchID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { directory.appendingPathComponent($0) }
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
            age: age,
            accountScopeID: AccountScope.current
        )
        connectivity.send(.preferences(preferences))
    }

    // MARK: - Incoming

    private func handle(_ message: SyncMessage) {
        switch message {
        case .workout(let matchID, let date, let report):
            WorkoutStore.shared.add(report, matchID: matchID, date: date)
            if let matchID, let record = MatchStore.shared.record(id: matchID) {
                // Health data stays on this phone. It's shared only when
                // the player posts a Replay that mentions it.
                record.workout = report
                AppDatabase.save()
            }
            MatchStore.shared.reload()
            return
        case .preferences, .crowd:
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
        case .endRequest(let matchID, _, _):
            // The Watch finished a match this phone hosted but is no longer
            // showing (the app was closed): apply its last taps, then end.
            guard let record = MatchStore.shared.record(id: matchID), let stored = record.setup else { return }
            var replica = MatchReplica(setup: stored, role: .host, log: record.rallyLog)
            let outcome = replica.receive(message)
            record.apply(log: replica.log, in: context)
            AppDatabase.save()
            connectivity.send(outcome.outgoing)
            if let reason = replica.ended { apply(reason, to: record) }
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
        var matchContext = MatchContext()
        matchContext.squadID = Social.shared.sharedSquad(for: setup.lineup.allPlayers.map(\.id))?.id
        record.matchContext = matchContext
        AppDatabase.save()
        let match = LiveMatch(setup: setup, role: .client, log: snapshot.rallies, context: matchContext,
                              revision: snapshot.revision)
        live = match
        activities.start(for: match)
        Social.shared.goLive(match)
    }

    /// A Watch that hasn't received the owner's ID yet labels them with a
    /// Watch-local user ID. Map an unknown user back to the owner — but only
    /// when the owner isn't already in the lineup, so friends picked on the
    /// Watch stay themselves.
    private func normalized(_ setup: MatchSetup) -> MatchSetup {
        let directory = PlayerDirectory.shared
        let me = directory.me
        guard !setup.lineup.allPlayers.contains(where: { $0.id == me.id }) else { return setup }
        var normalized = setup
        var mapped = false
        normalized.lineup.teams = setup.lineup.teams.map { roster in
            roster.map { player in
                guard !mapped, player.kind == .user, directory.player(player.id) == nil else { return player }
                mapped = true
                return me
            }
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
        if outcome.changed, !match.isEnded {
            Social.shared.updateLive(match)
            if match.photoPrompter.shouldPrompt(after: outcome.events, at: Date()) {
                match.photoPrompter.didPrompt(at: Date())
                match.photoPromptVisible = true
            }
        }

        guard let record = MatchStore.shared.record(id: match.id) else { return }
        if outcome.changed {
            // Finished here as the client: save the score the player saw;
            // the host's final log replaces it when it arrives.
            let rallies = match.replica.isAwaitingEndAck ? match.replica.scorer.rallies : match.replica.log
            record.apply(log: rallies, in: context)
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
            if !alreadyCompleted {
                if let match { match.onCompleted?(match.result) }
                Task { await Social.shared.upload(record) }
                if let result = record.result {
                    let drama = DramaDetector.analyze(rules: record.rules ?? .standard(for: record.sport), rallies: record.rallyLog)
                    // Belts wait for the other side to confirm; a comeback
                    // is worth sharing straight away.
                    Social.shared.offerShareCard(for: result, beltEvents: [], drama: drama)
                }
            }
        case .completed, .parked:
            record.status = .parked
            AppDatabase.save()
        case .abandoned:
            context.delete(record)
            AppDatabase.save()
        }
        MatchStore.shared.reload()

        if let match {
            Social.shared.endLive(match.id)
        }
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

    // MARK: - Watch-owned matches (journal)

    private static var journalDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatchJournal", isDirectory: true)
    }

    private static var phoneDeviceID: UUID {
        let key = "phone.deviceID"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    private func openJournal() {
        do {
            journal = try MatchCoordinator(store: FileMatchEventStore(root: Self.journalDirectory), deviceID: Self.phoneDeviceID)
        } catch {
            Social.shared.notice = String(localized: "Matches from your Apple Watch can’t be saved on this iPhone right now.")
            return
        }
        handoff = WatchHandoff.load(from: Self.journalDirectory)
        importAllJournals()
        resendHandoff()
    }

    /// Re-files every Watch match for the account now signed in (after a
    /// launch or an account switch).
    func importAllJournals() {
        guard let journal else { return }
        Task {
            for entry in await journal.allJournals() where entry.role == .mirror {
                importJournal(entry)
            }
        }
    }

    private func handleJournal(_ messages: [JournalMessage]) {
        guard let journal else { return }
        Task {
            for message in messages {
                handleHandoffSignal(message)
                do {
                    let replies = try await journal.receive(message)
                    connectivity.sendJournal(replies)
                } catch {
                    // Nothing was acknowledged; the Watch will resend.
                    Social.shared.notice = String(localized: "Couldn’t save a match from your Apple Watch. Free up some storage.")
                    continue
                }
                if let matchID = message.matchID, let entry = await journal.journal(matchID), entry.role == .mirror {
                    importJournal(entry)
                }
            }
        }
    }

    /// Mirrors a Watch match into history: live while it's being played
    /// (read-only here), completed once every operation up to the finish is
    /// saved. Matches for another account wait until that account signs in.
    private func importJournal(_ entry: MatchJournal) {
        let scope = entry.manifest.accountScopeID
        guard scope == nil || scope == AccountScope.current else { return }
        var setup = normalized(entry.manifest.setup)
        setup.host = .watch
        PlayerDirectory.shared.adopt(setup.lineup)
        let record = MatchStore.shared.record(id: entry.matchID) ?? {
            let record = MatchRecord(setup: setup, status: .live)
            record.ownerAccountID = scope
            context.insert(record)
            return record
        }()
        // A result the phone already completed and uploaded stays as it is.
        guard record.status != .completed else { return }
        record.hostRaw = DeviceRole.watch.rawValue
        record.sourceRaw = MatchSource.watch.rawValue
        record.apply(log: entry.rallies, in: context)
        AppDatabase.save()

        if entry.isComplete {
            if handoff?.matchID == entry.matchID { setHandoff(nil) }
            let mirror = live?.id == entry.matchID ? live : nil
            if let mirror {
                mirror.replica = MatchReplica(setup: setup, role: .client, log: entry.rallies,
                                              ended: entry.status == .finished ? .completed : .abandoned)
                mirror.revision += 1
            }
            if let finished = entry.finishOperation { record.endedAt = finished.occurredAt }
            apply(entry.status == .finished ? .completed : .abandoned, to: record, match: mirror)
            return
        }

        record.status = .live
        AppDatabase.save()
        MatchStore.shared.reload()
        if handoff?.matchID == entry.matchID, handoff?.state != .scoringOnWatch {
            var updated = handoff
            updated?.state = .scoringOnWatch
            setHandoff(updated)
        }
        // Show it here too, read-only, if the phone isn't busy.
        if let match = live, match.id == entry.matchID {
            match.replica = MatchReplica(setup: setup, role: .client, log: entry.rallies)
            match.revision += 1
            Social.shared.updateLive(match)
            activities.update(for: match)
        } else if live == nil || live?.isEnded == true {
            var matchContext = record.matchContext
            if matchContext.squadID == nil {
                matchContext.squadID = Social.shared.sharedSquad(for: setup.lineup.allPlayers.map(\.id))?.id
            }
            let match = LiveMatch(setup: setup, role: .client, log: entry.rallies, context: matchContext)
            match.isWatchOwned = true
            live = match
            activities.start(for: match)
            Social.shared.goLive(match)
        }
    }

    // MARK: - Handing a match to the Watch

    /// Saves a draft for a match set up here and asks the Watch to get
    /// ready. Phone scoring stays possible until Start.
    func prepareWatchMatch(rules: MatchRules, lineup: Lineup, context matchContext: MatchContext = MatchContext()) {
        let setup = MatchSetup(rules: rules, lineup: lineup, host: .watch, tournamentMatchID: matchContext.fixtureID)
        let me = PlayerDirectory.shared.me.id
        let wearer = Team.allCases.first { team in lineup.teams[team].contains { $0.id == me } }
        let draft = MatchDraft(setup: setup, accountScopeID: AccountScope.current, wearerTeam: wearer)
        setHandoff(WatchHandoff(draft: draft, grantID: nil, state: .preparing))
        connectivity.sendJournal([.draft(draft)])
        connectivity.wakeWatchForMatch(sport: rules.sport)
    }

    /// The player's Start: the Watch becomes the scoring owner. From here a
    /// timeout never quietly gives scoring back to the phone; only an
    /// accepted cancel does.
    func startOnWatch() {
        guard var current = handoff, current.grantID == nil else { return resendHandoff() }
        current.grantID = UUID()
        current.state = .starting
        setHandoff(current)
        resendHandoff()
    }

    /// Takes the match back. Before Start it's simply dropped; after Start
    /// the Watch must agree (it refuses once a rally has been scored).
    func cancelWatchHandoff() {
        guard var current = handoff else { return }
        if let grantID = current.grantID {
            current.state = .cancelling
            setHandoff(current)
            connectivity.sendJournal([.grantCancel(grantID: grantID, matchID: current.matchID)])
        } else {
            connectivity.sendJournal([.grantCancel(grantID: UUID(), matchID: current.matchID)])
            setHandoff(nil)
        }
    }

    /// Sends the draft or grant again (the Watch answers repeats the same way).
    private func resendHandoff() {
        guard let current = handoff else { return }
        switch current.state {
        case .preparing, .ready:
            connectivity.sendJournal([.draft(current.draft)])
        case .starting:
            if let grantID = current.grantID {
                connectivity.sendJournal([.grant(ScoringGrant(grantID: grantID, draft: current.draft, issuedAt: current.updatedAt))])
            }
        case .cancelling:
            if let grantID = current.grantID {
                connectivity.sendJournal([.grantCancel(grantID: grantID, matchID: current.matchID)])
            }
        case .scoringOnWatch:
            break
        }
    }

    private func handleHandoffSignal(_ message: JournalMessage) {
        switch message {
        case .unsupportedVersion:
            watchNeedsUpdate = true
        case .draftReady(let matchID, let version):
            guard var current = handoff, current.matchID == matchID, current.state == .preparing,
                  version >= current.draft.draftVersion else { return }
            current.state = .ready
            setHandoff(current)
        case .grantAccepted(let grantID, let matchID, _):
            guard var current = handoff, current.matchID == matchID else { return }
            // Accepted under this grant or the Watch already started it itself.
            current.grantID = current.grantID ?? grantID
            current.state = .scoringOnWatch
            setHandoff(current)
        case .grantCancelled(_, let matchID, let accepted):
            guard let current = handoff, current.matchID == matchID else { return }
            if accepted {
                // The Watch confirmed it holds nothing: the phone may score.
                setHandoff(nil)
            } else if current.state == .cancelling {
                // Too late to take back: the Watch keeps scoring it.
                var updated = current
                updated.state = .scoringOnWatch
                setHandoff(updated)
                Social.shared.notice = String(localized: "Your Watch has already started scoring this match.")
            } else if current.state == .starting {
                // The Watch refused the grant, so it never became the owner.
                setHandoff(nil)
                Social.shared.notice = String(localized: "Your Watch is busy with another match.")
            }
        case .manifest(let manifest):
            if var current = handoff, current.matchID == manifest.matchID, current.state != .scoringOnWatch {
                current.state = .scoringOnWatch
                setHandoff(current)
            }
        default:
            break
        }
    }

    private func setHandoff(_ value: WatchHandoff?) {
        handoff = value.map { var copy = $0; copy.updatedAt = Date(); return copy }
        WatchHandoff.save(handoff, to: Self.journalDirectory)
    }
}
