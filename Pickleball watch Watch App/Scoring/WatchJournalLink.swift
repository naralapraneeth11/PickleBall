//
//  WatchJournalLink.swift
//  Pickleball watch Watch App
//
//  Watch-owned scoring. The MatchCoordinator (CourtKit) keeps every match
//  in a durable journal on the Watch; this file connects it to the UI and
//  to WatchConnectivity.
//
//  Order for every tap: save on the Watch → update the score and buzz →
//  try to send. The phone saves what it gets and returns a receipt; until
//  then the operations are resent (immediately when reachable, otherwise
//  as one queued batch), so disconnects, crashes and late delivery lose
//  nothing and double count nothing.
//

import Foundation
import WatchConnectivity
import WatchKit
import CourtKit

extension WatchMatchSession {
    private enum JournalKeys {
        static let deviceID = "watch.deviceID"
    }

    /// Where the journal lives. Application Support survives restarts and
    /// isn't purged like caches.
    private static var journalDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatchJournal", isDirectory: true)
    }

    /// This Watch's stable identity as a scoring owner.
    private var deviceID: UUID {
        if let raw = defaults.string(forKey: JournalKeys.deviceID), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: JournalKeys.deviceID)
        return id
    }

    // MARK: Opening

    /// Loads the journal and picks up a match that was being played when
    /// the app stopped.
    func openJournal() {
        do {
            coordinator = try MatchCoordinator(store: FileMatchEventStore(root: Self.journalDirectory), deviceID: deviceID)
        } catch {
            saveError = String(localized: "Matches can’t be saved on this Watch right now.")
            return
        }
        Task {
            await migrateLegacyHostedMatch()
            await refreshOwned(restoring: true)
            flushJournal()
        }
    }

    private func migrateLegacyHostedMatch() async {
        guard let coordinator, let snapshot = legacyHostedMatch() else { return }
        do {
            let journal = try await coordinator.startMatch(setup: snapshot.setup, accountScopeID: preferences.accountScopeID,
                                                           wearerTeam: wearerTeam(in: snapshot.setup.lineup), role: .watch,
                                                           at: snapshot.setup.startedAt)
            for rally in snapshot.rallies {
                try await coordinator.perform(.rallyWon(rally.winner), in: journal.matchID, at: rally.at)
            }
        } catch {
            saveError = String(localized: "A match from before the update couldn’t be moved.")
        }
    }

    /// The wearer's team in a lineup (the side the device owner is on).
    func wearerTeam(in lineup: Lineup) -> Team? {
        Team.allCases.first { team in lineup.teams[team].contains { $0.id == me.id } }
    }

    // MARK: Starting

    func startOwnedMatch(_ setup: MatchSetup) {
        guard let coordinator else { return }
        Task {
            do {
                let journal = try await coordinator.startMatch(setup: setup, accountScopeID: preferences.accountScopeID,
                                                               wearerTeam: wearerTeam(in: setup.lineup), role: .watch)
                show(journal)
                WorkoutManager.shared.start(sport: setup.rules.sport, matchID: setup.matchID)
                flushJournal()
            } catch {
                report(error)
            }
        }
    }

    /// The player tapped Start on a match set up on the phone. The Watch
    /// becomes the owner; the phone learns from the manifest.
    func startPendingDraft() {
        guard let draft = pendingDraft, let coordinator else { return }
        Task {
            do {
                var setup = draft.setup
                setup.host = .watch
                let journal = try await coordinator.startMatch(setup: setup, accountScopeID: draft.accountScopeID,
                                                               wearerTeam: draft.wearerTeam ?? wearerTeam(in: setup.lineup),
                                                               role: .watch)
                pendingDraft = nil
                show(journal)
                WorkoutManager.shared.start(sport: setup.rules.sport, matchID: setup.matchID)
                flushJournal()
            } catch {
                report(error)
            }
        }
    }

    // MARK: Scoring

    /// Saves an action, then updates the score and buzzes. Nothing changes
    /// on screen if the save fails.
    func performOwned(_ action: MatchOperationPayload) {
        guard let coordinator, let current = ownedJournal else { return }
        let matchID = current.matchID
        // Work out the haptic from the score before the save.
        var preview = current.scorer
        var events: [ScoreEvent] = []
        if case .rallyWon(let team) = action { events = preview.recordRally(wonBy: team) }
        Task {
            do {
                let journal = try await coordinator.perform(action, in: matchID)
                saveError = nil
                show(journal)
                switch action {
                case .rallyWon:
                    lastEvents = events
                    Haptics.play(events)
                case .undo:
                    Haptics.soft()
                case .finished, .abandoned:
                    // The workout saves on its own time; the score is done.
                    WorkoutManager.shared.finish(matchID: journal.matchID, sendsReport: journal.status == .finished)
                case .paused:
                    WorkoutManager.shared.pause()
                    Haptics.selection()
                case .resumed:
                    WorkoutManager.shared.resume()
                    Haptics.selection()
                default:
                    Haptics.selection()
                }
                flushJournal()
            } catch JournalError.invalidAction {
                Haptics.warning()
            } catch JournalError.matchClosed {
                Haptics.warning()
            } catch {
                report(error)
            }
        }
    }

    func pauseOrResume() {
        guard let journal = ownedJournal else { return }
        performOwned(journal.status == .paused ? .resumed : .paused)
    }

    var isPaused: Bool { ownedJournal?.status == .paused }

    func dismissOwned(_ matchID: UUID) {
        guard let coordinator else { return }
        Task {
            try? await coordinator.dismiss(matchID)
            await refreshOwned(restoring: false)
        }
    }

    /// Queues a workout summary for the iPhone. WatchConnectivity keeps
    /// queued transfers across relaunches until they're delivered.
    func queue(workout message: SyncMessage) -> Bool {
        guard let session, session.activationState == .activated else { return false }
        session.transferUserInfo(message.wcPayload)
        return true
    }

    private func report(_ error: Error) {
        saveError = String(localized: "Couldn’t save on this Watch. Free up some storage.")
        Haptics.warning()
    }

    // MARK: Showing

    /// Puts a journal on screen through the same score views as before.
    func show(_ journal: MatchJournal) {
        ownedJournal = journal
        let ended: EndReason? = switch journal.status {
        case .finished: .completed
        case .abandoned: .abandoned
        default: nil
        }
        replica = MatchReplica(setup: journal.manifest.setup, role: .host, log: journal.rallies, ended: ended)
        sport = journal.manifest.setup.rules.sport
        revision += 1
        if journal.status == .abandoned {
            // Nothing to show for an abandoned match.
            replica = nil
            ownedJournal = nil
        }
    }

    /// Re-reads sync counts and, after a restart, the match in progress.
    func refreshOwned(restoring: Bool) async {
        guard let coordinator else { return }
        let unsynced = await coordinator.unsyncedOwnedMatches()
        unsyncedOwnedCount = unsynced.filter { $0.status.isTerminal }.count
        if let current = ownedJournal, let updated = await coordinator.journal(current.matchID) {
            ownedJournal = updated
        } else if restoring, replica == nil, let active = await coordinator.activeOwnedMatch() {
            show(active)
            WorkoutManager.shared.start(sport: active.manifest.setup.rules.sport, matchID: active.matchID)
        }
    }

    /// Sync state for the match on screen.
    var ownedSyncNote: String? {
        guard let journal = ownedJournal else { return nil }
        if journal.unacknowledged.isEmpty { return String(localized: "Synced to iPhone") }
        return String(localized: "Saved on Watch · sync pending")
    }

    // MARK: Sending

    /// Sends everything the phone hasn't confirmed. Reachable: right away.
    /// Otherwise one queued batch replaces any earlier queued batch, so the
    /// system queue never fills with one transfer per tap.
    func flushJournal() {
        guard let coordinator else { return }
        Task {
            let messages = await coordinator.outgoing()
            send(journal: messages)
            scheduleRetry(hasPending: !messages.isEmpty)
        }
    }

    func send(journal messages: [JournalMessage]) {
        guard !messages.isEmpty, let session, session.activationState == .activated else { return }
        let payload = JournalMessage.batchPayload(messages)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.queue(payload) }
            }
        } else {
            queue(payload)
        }
    }

    private func queue(_ payload: [String: Any]) {
        guard let session else { return }
        for transfer in session.outstandingUserInfoTransfers where transfer.userInfo[JournalMessage.batchKey] != nil {
            transfer.cancel()
        }
        session.transferUserInfo(payload)
    }

    /// While something is unconfirmed and the app is running, try again
    /// every so often (receipts can be lost too).
    private func scheduleRetry(hasPending: Bool) {
        retryTask?.cancel()
        guard hasPending else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.flushJournal()
        }
    }

    // MARK: Receiving

    func deliverJournal(_ messages: [JournalMessage]) {
        guard !messages.isEmpty, let coordinator else { return }
        let previous = incomingWork
        incomingWork = Task {
            await previous?.value
            for message in messages {
                switch message {
                case .unsupportedVersion:
                    needsUpdate = true
                    continue
                case .draft(let draft):
                    if ownedJournal == nil { pendingDraft = draft }
                case .grantCancel(_, let matchID):
                    if pendingDraft?.matchID == matchID { pendingDraft = nil }
                default:
                    break
                }
                do {
                    let replies = try await coordinator.receive(message)
                    send(journal: replies)
                    if case .grant(let grant) = message, let journal = await coordinator.journal(grant.matchID),
                       !journal.status.isTerminal {
                        // The phone handed scoring over: show it.
                        pendingDraft = nil
                        if ownedJournal == nil, replica == nil {
                            show(journal)
                            WorkoutManager.shared.start(sport: journal.manifest.setup.rules.sport, matchID: journal.matchID)
                        }
                    }
                    if case .grantCancel(_, let matchID) = message, ownedJournal?.matchID == matchID,
                       let journal = await coordinator.journal(matchID) {
                        show(journal)
                    }
                } catch {
                    report(error)
                }
            }
            await refreshOwned(restoring: false)
        }
    }

    /// For the WatchConnectivity background task: returns once received
    /// data has been saved.
    func finishBackgroundWork() async {
        await incomingWork?.value
    }
}
