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
        for record in (try? AppDatabase.context.fetch(descriptor)) ?? [] where record.createdByID == nil || record.createdByID == userID {
            await upload(record)
        }
    }

    // MARK: Down

    func refreshMatches() async {
        guard let backend, phase == .ready else { return }
        do {
            let rows = try await backend.matches(updatedAfter: matchCursor)
            if !rows.isEmpty {
                let participantRows = try await backend.participants(matchIDs: rows.map(\.id))
                let playerIDs = Set(participantRows.map(\.playerID))
                let playerRows = try await backend.players(ids: Array(playerIDs))
                mergePlayers(playerRows)
                let byMatch = Dictionary(grouping: participantRows, by: \.matchID)
                for row in rows {
                    merge(row, participants: byMatch[row.id] ?? [])
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
        } catch {
            report(error)
        }
        await uploadUnsentMatches()
    }

    private func pendingMatchIDs() -> [UUID] {
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.confirmationRaw == pending })
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).map(\.id)
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
        record.confirmation = MatchConfirmation(row.status)
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
        if record.workout == nil, let workout = row.workout { record.workout = workout }
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
            guard record.createdByID != userID, let parts = pendingParticipants[record.id],
                  let mine = parts.first(where: { playerUser($0.playerID) == userID }) else { return false }
            return parts.filter { $0.team == mine.team }.allSatisfy { $0.confirmedAt == nil }
        }
    }

    /// Results I recorded that are waiting on the other side.
    var awaitingTheirConfirmation: [MatchRecord] {
        guard let userID else { return [] }
        let pending = MatchConfirmation.pending.rawValue
        let descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.confirmationRaw == pending })
        return ((try? AppDatabase.context.fetch(descriptor)) ?? []).filter { $0.createdByID == userID }
    }

    /// The account behind a player row (claimed guests count as their owner).
    func playerUser(_ playerID: UUID) -> UUID? {
        if let row = players[playerID] { return row.userID }
        return profiles[playerID] != nil || playerID == userID ? playerID : nil
    }

    func confirm(_ record: MatchRecord, agree: Bool) async {
        var events: [ChatEvent] = []
        if agree, let result = record.result {
            // What this result does to the belts, from everything confirmed so far.
            var ledger = BeltLedger.compute(MatchStore.shared.confirmedResults.filter { $0.id != record.id })
            events = ledger.record(result).map(ChatEvent.belt)
        }
        do {
            await enqueue(try Operations.confirmMatch(record.id, agree: agree, events: events))
            record.confirmation = agree ? .confirmed : .disputed
            AppDatabase.save()
            MatchStore.shared.reload()
            if agree, let result = record.result {
                offerShareCard(for: result, beltEvents: events.compactMap {
                    if case .belt(let event) = $0 { return event } else { return nil }
                }, drama: nil)
            }
        } catch {
            report(error)
        }
    }

    func withdraw(_ record: MatchRecord) async {
        let id = record.id
        let ok = await run { try await $0.withdrawMatch(id) }
        if ok { MatchStore.shared.delete(matchID: id) }
    }
}
