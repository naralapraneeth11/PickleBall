//
//  Social+Matches.swift
//  PickleBall
//
//  Matches between SwiftData and Supabase.
//
//  • Up: a finished match goes into the outbox (save_match). Watch- and
//    phone-scored matches carry their rally log; typed-in scores carry
//    game scores. Offline, it waits; the scorer still sees it at once.
//  • Down: matches friends and squadmates recorded (and ours, with their
//    confirmation status) are merged into SwiftData by ID, so stats,
//    head-to-head and belts all read one store.
//  • Confirm: the other side agrees or disputes. The confirming phone works
//    out what the result did to the belts and posts that to chat.
//

import Foundation
import SwiftData
import CourtKit
import CourtNet

extension Social {
    // MARK: Up

    /// Queues a finished match for upload. Safe to call again (a later
    /// version replaces a queued one).
    func upload(_ record: MatchRecord) async {
        guard phase == .ready, let userID else { return }
        // Only this account's own history goes up: never a match scored by
        // someone else on a shared phone.
        guard record.ownerAccountID == userID else { return }
        guard record.status == .completed, record.confirmation != .confirmed else { return }
        guard record.createdByID == nil || record.createdByID == userID else { return }
        guard let lineup = record.lineup, lineup.team(of: PlayerID(rawValue: userID)) != nil || record.tournamentID != nil else { return }
        record.createdByID = userID
        AppDatabase.save()
        guard let request = record.uploadRequest else { return }
        do {
            await enqueue(try Operations.saveMatch(request))
        } catch {
            report(error)
        }
    }

    /// Everything finished on this phone that the server hasn't seen.
    func uploadUnsentMatches() async {
        guard let userID else { return }
        let completed = MatchStatus.completed.rawValue
        let local = MatchConfirmation.local.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate {
            $0.statusRaw == completed && $0.confirmationRaw == local
        })
        for record in (try? AppDatabase.context.fetch(descriptor)) ?? []
        where record.ownerAccountID == userID && (record.createdByID == nil || record.createdByID == userID) {
            await upload(record)
        }
    }

    // MARK: Down

    func refreshMatches() async {
        guard let backend, phase == .ready else { return }
        var newlyConfirmed: [UUID] = []
        do {
            // A full read (first sync, or after becoming friends or joining
            // a squad) also catches older matches and drops ones no longer visible.
            let isFullSync = matchCursor == nil
            // A second of overlap, so a row written as the last page was read
            // isn't skipped; merging is idempotent.
            let rows = try await backend.matches(updatedSince: matchCursor?.addingTimeInterval(-1))
            if isFullSync { removeMatchesNoLongerVisible(keeping: Set(rows.map(\.id))) }
            if !rows.isEmpty {
                let participantRows = try await backend.participants(matchIDs: rows.map(\.id))
                let playerIDs = Set(participantRows.map(\.playerID))
                let playerRows = try await backend.players(ids: Array(playerIDs))
                mergePlayers(playerRows)
                let byMatch = Dictionary(grouping: participantRows, by: \.matchID)
                for row in rows {
                    let before = MatchStore.shared.record(id: row.id)?.confirmation
                    merge(row, participants: byMatch[row.id] ?? [])
                    // Final now, by the server's word: a result I recorded or
                    // played in. Rewards wait for this, never for a tap.
                    let playedIn = byMatch[row.id]?.contains { playerUser($0.playerID) == userID } ?? false
                    if row.status == .confirmed, before == .pending || before == .local,
                       row.createdBy == userID || playedIn {
                        newlyConfirmed.append(row.id)
                    }
                }
                AppDatabase.save()
                matchCursor = rows.compactMap(\.updatedAt).max() ?? matchCursor
            }
            // Keep confirmation details fresh for anything still pending.
            let pendingIDs = pendingMatchIDs()
            if !pendingIDs.isEmpty {
                let rows = try await backend.participants(matchIDs: pendingIDs)
                setPendingParticipants(Dictionary(grouping: rows, by: \.matchID))
            } else {
                setPendingParticipants([:])
            }
            MatchStore.shared.reload()
            scheduleCacheSave()
            // Belt won (or upgraded) now that it counts: offer the card.
            for id in newlyConfirmed {
                guard let result = MatchStore.shared.record(id: id)?.result else { continue }
                let events = MatchStore.shared.belts.events(for: id)
                if events.contains(where: \.isShareWorthy) {
                    offerShareCard(for: result, beltEvents: events, drama: nil)
                    break
                }
            }
        } catch {
            report(error)
        }
        await uploadUnsentMatches()
    }

    private func pendingMatchIDs() -> [UUID] {
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.confirmationRaw == pending })
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).filter { $0.ownerAccountID == userID }.map(\.id)
    }

    /// After a full read: synced matches the server no longer shows me
    /// (withdrawn, deleted, or from someone I'm no longer connected to)
    /// leave this phone. My own unsent matches stay.
    private func removeMatchesNoLongerVisible(keeping visible: Set<UUID>) {
        guard let userID else { return }
        let all = (try? AppDatabase.context.fetch(FetchDescriptor<MatchRecord>())) ?? []
        var removed = false
        for record in all where record.ownerAccountID == userID && record.remoteUpdatedAt != nil
            && record.confirmation != .local && !visible.contains(record.id) && record.status == .completed {
            AppDatabase.context.delete(record)
            removed = true
        }
        if removed { AppDatabase.save() }
    }

    /// Becoming friends or joining a squad can reveal older matches the
    /// incremental read would skip; losing a connection hides some. Either
    /// way, read everything again.
    func noteVisibilityChange() {
        let me = userID
        let friends = friendships.filter { $0.status == .accepted }.compactMap { row in me.map { row.other(than: $0) } }
        let key = Set(friends.map { "f:\($0)" } + squads.map { "s:\($0.id)" })
        defer { visibilityKey = key }
        guard let previous = visibilityKey, previous != key else { return }
        matchCursor = nil
        Task { await refreshMatches() }
    }

    /// Creates or updates the local copy of a server match.
    private func merge(_ row: MatchRow, participants: [ParticipantRow]) {
        let lineup = MatchWire.lineup(participants: participants, players: players)
        let context = AppDatabase.context
        let record: MatchRecord
        if let existing = MatchStore.shared.record(id: row.id) {
            record = existing
            record.lineupData = (try? JSONEncoder().encode(lineup)) ?? record.lineupData
            record.playerIDs = lineup.allPlayers.map(\.id.rawValue)
        } else {
            let setup = MatchSetup(matchID: row.id, rules: row.rules, lineup: lineup, startedAt: row.startedAt, host: .phone,
                                   tournamentMatchID: row.fixtureID)
            record = MatchRecord(setup: setup, status: .completed)
            context.insert(record)
            if let rallies = MatchWire.rallies(row) {
                record.apply(log: rallies, in: context)
            }
            PlayerDirectory.shared.adopt(lineup)
        }

        record.status = .completed
        record.source = row.source
        record.ownerAccountID = userID
        record.confirmation = MatchConfirmation(row.status)
        // The server has answered; anything I sent is settled.
        if row.status != .pending { record.myAnswerRaw = nil }
        record.createdByID = row.createdBy
        record.endedAt = row.endedAt ?? row.startedAt
        record.remoteUpdatedAt = row.updatedAt
        record.matchContext = MatchContext(court: row.court, squadID: row.squadID, tournamentID: row.tournamentID,
                                           fixtureID: row.fixtureID, calloutID: row.calloutID)
        if record.rallies.isEmpty {
            // Typed-in scores (or a server copy without a log).
            record.winnerRaw = row.winnerTeam?.rawValue
            record.matchScoreA = row.matchScore.first ?? 0
            record.matchScoreB = row.matchScore.dropFirst().first ?? 0
            record.pointsA = row.points.first ?? 0
            record.pointsB = row.points.dropFirst().first ?? 0
            record.unitsData = try? JSONEncoder().encode(row.units)
        }
    }

    // MARK: Confirming

    /// Results someone else recorded that my side hasn't agreed to yet.
    var awaitingMyConfirmation: [MatchRecord] {
        guard let userID else { return [] }
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(
            predicate: #Predicate { $0.confirmationRaw == pending },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).filter { record in
            guard record.ownerAccountID == userID, record.myAnswerRaw == nil,
                  record.createdByID != userID, let parts = pendingParticipants[record.id],
                  let mine = parts.first(where: { playerUser($0.playerID) == userID }) else { return false }
            return parts.filter { $0.team == mine.team }.allSatisfy { $0.confirmedAt == nil }
        }
    }

    /// Results I recorded that are waiting on the other side.
    var awaitingTheirConfirmation: [MatchRecord] {
        guard let userID else { return [] }
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.confirmationRaw == pending })
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).filter { $0.createdByID == userID && $0.ownerAccountID == userID }
    }

    /// Answers I've sent that the server hasn't settled yet.
    var answersOnTheirWay: [MatchRecord] {
        guard let userID else { return [] }
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.confirmationRaw == pending })
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).filter { $0.myAnswerRaw != nil && $0.ownerAccountID == userID }
    }

    /// The account behind a player row (claimed guests count as their owner).
    func playerUser(_ playerID: UUID) -> UUID? {
        if let row = players[playerID] { return row.userID }
        return profiles[playerID] != nil || playerID == userID ? playerID : nil
    }

    /// Sends my confirm or dispute. The result is final only when the
    /// server says so (the other side may still be pending, or it may
    /// refuse): until then the match shows "your answer is on its way", and
    /// belts and share cards wait.
    func confirm(_ record: MatchRecord, agree: Bool) async {
        var events: [ChatEvent] = []
        if agree, let result = record.result {
            // What this result does to the belts, from everything confirmed so
            // far. The server posts these only if the match becomes final.
            var ledger = BeltLedger.compute(MatchStore.shared.confirmedResults.filter { $0.id != record.id })
            events = ledger.record(result).map(ChatEvent.belt)
        }
        do {
            await enqueue(try Operations.confirmMatch(record.id, agree: agree, events: events))
            record.myAnswerRaw = agree ? "agree" : "dispute"
            AppDatabase.save()
            MatchStore.shared.reload()
            // Online, the answer is already sent: read back what it did.
            await refreshMatches()
        } catch {
            report(error)
        }
    }

    /// A confirm or dispute the server refused: let the player answer again.
    func clearRefusedAnswers(_ refused: [OutboxOperation]) {
        var changed = false
        for operation in refused {
            guard case .rpc(let name, let params) = operation.action, name == "confirm_match",
                  case .object(let fields) = params, case .string(let raw)? = fields["mid"],
                  let id = UUID(uuidString: raw),
                  let record = MatchStore.shared.record(id: id), record.myAnswerRaw != nil else { continue }
            record.myAnswerRaw = nil
            changed = true
        }
        if changed {
            AppDatabase.save()
            MatchStore.shared.reload()
        }
    }

    func withdraw(_ record: MatchRecord) async {
        let id = record.id
        let ok = await run { try await $0.withdrawMatch(id) }
        if ok { MatchStore.shared.delete(matchID: id) }
    }
}
