//
//  MatchCoordinator.swift
//  CourtKit
//
//  Serialises everything that changes a match journal on one device: score
//  commands on the owner, incoming operations on the mirror, receipts,
//  resends, drafts and scoring grants. Each change is written to the store
//  before it's applied in memory, so what the UI shows (and what the other
//  device is told) has always been saved. If saving fails, the command
//  throws and nothing changes.
//
//  Transport-free: callers pass in received messages and send what comes
//  back. That makes every fault scenario testable without a Watch.
//

import Foundation

public actor MatchCoordinator {
    /// Matches waiting for their manifest are kept, within limits.
    public static let inboxLimit = 2_000
    /// Operations per message batch.
    public static let batchSize = 60

    public let deviceID: UUID
    private let store: MatchEventStore
    private var journals: [UUID: MatchJournal] = [:]
    private var drafts: [UUID: MatchDraft] = [:]
    private var inbox: [MatchOperation] = []
    /// Grant IDs already accepted, to answer repeats identically.
    private var acceptedGrants: [UUID: UUID] = [:]

    /// Loads everything saved. Throws if the store can't be read at all.
    public init(store: MatchEventStore, deviceID: UUID) throws {
        self.store = store
        self.deviceID = deviceID
        let loaded = try store.loadJournals()
        journals = Dictionary(loaded.map { ($0.matchID, $0) }, uniquingKeysWith: { first, _ in first })
        drafts = Dictionary((try store.loadDrafts()).map { ($0.matchID, $0) }, uniquingKeysWith: { first, _ in first })
        inbox = try store.loadInbox()
        for journal in loaded {
            if let grant = journal.manifest.grantID { acceptedGrants[grant] = journal.matchID }
        }
    }

    // MARK: Reading

    public func journal(_ matchID: UUID) -> MatchJournal? { journals[matchID] }

    /// Every match on this device, newest first.
    public func allJournals() -> [MatchJournal] {
        journals.values.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    public func draft(_ matchID: UUID) -> MatchDraft? { drafts[matchID] }

    /// The match being played here, if any (owned, not closed).
    public func activeOwnedMatch() -> MatchJournal? {
        allJournals().first { $0.role == .owner && !$0.status.isTerminal }
    }

    /// Owned matches the other device hasn't fully confirmed.
    public func unsyncedOwnedMatches() -> [MatchJournal] {
        allJournals().filter { $0.role == .owner && !$0.unacknowledged.isEmpty }
    }

    // MARK: Owner commands

    /// Starts a match owned by this device.
    @discardableResult
    public func startMatch(setup: MatchSetup, accountScopeID: UUID?, wearerTeam: Team?,
                           role ownerRole: DeviceRole, authorityEpoch: Int64 = 1, grantID: UUID? = nil,
                           at date: Date = Date()) throws -> MatchJournal {
        if let existing = journals[setup.matchID] { return existing }
        let manifest = MatchManifest(setup: setup, accountScopeID: accountScopeID, ownerDeviceID: deviceID,
                                     ownerRole: ownerRole, authorityEpoch: authorityEpoch, wearerTeam: wearerTeam,
                                     grantID: grantID, createdAt: date)
        let journal = MatchJournal.owned(manifest, startedAt: date)
        try commit(journal)
        return journal
    }

    /// Records an action on an owned match. Saved before it returns.
    @discardableResult
    public func perform(_ action: MatchOperationPayload, in matchID: UUID, at date: Date = Date()) throws -> MatchJournal {
        guard var journal = journals[matchID] else { throw JournalError.foreign("unknown match") }
        try journal.append(action, at: date)
        try commit(journal)
        return journal
    }

    /// Hides a finished match from the result screen. The record stays
    /// until the other device has it (and longer, under retention).
    public func dismiss(_ matchID: UUID) throws {
        guard var journal = journals[matchID] else { return }
        journal.isDismissed = true
        try commit(journal)
    }

    /// Everything the other device still needs: each owned match's manifest
    /// (until confirmed) and unconfirmed operations, in batches. Safe to
    /// call repeatedly; receivers ignore duplicates.
    public func outgoing() -> [JournalMessage] {
        var messages: [JournalMessage] = []
        for journal in allJournals().reversed() where journal.role == .owner {
            let pending = journal.unacknowledged
            guard !pending.isEmpty else { continue }
            if journal.acknowledgedSequence == 0 { messages.append(.manifest(journal.manifest)) }
            for start in stride(from: 0, to: pending.count, by: Self.batchSize) {
                let batch = Array(pending[start..<min(start + Self.batchSize, pending.count)])
                messages.append(.operations(matchID: journal.matchID, batch))
            }
        }
        return messages
    }

    // MARK: Receiving

    /// Handles one message from the other device and returns the replies to
    /// send. Throws only when saving fails (nothing was acknowledged then).
    public func receive(_ message: JournalMessage) throws -> [JournalMessage] {
        switch message {
        case .manifest(let manifest):
            return try receiveManifest(manifest)
        case .operations(let matchID, let operations):
            return try receiveOperations(matchID: matchID, operations)
        case .receipt(let receipt):
            guard var journal = journals[receipt.matchID], journal.role == .owner else { return [] }
            let before = journal.acknowledgedSequence
            journal.acknowledge(receipt)
            if journal.acknowledgedSequence != before { try commit(journal) }
            // The receiver is behind what it confirmed? Nothing to do; it
            // will ask. Ahead of what we sent? Impossible by construction.
            return []
        case .resend(let matchID, let from, let needsManifest):
            guard let journal = journals[matchID], journal.role == .owner else { return [] }
            var replies: [JournalMessage] = needsManifest ? [.manifest(journal.manifest)] : []
            let operations = journal.operations(from: max(1, from), limit: Int.max)
            for start in stride(from: 0, to: operations.count, by: Self.batchSize) {
                replies.append(.operations(matchID: matchID,
                                           Array(operations[start..<min(start + Self.batchSize, operations.count)])))
            }
            return replies
        case .draft(let draft):
            return try receiveDraft(draft)
        case .grant(let grant):
            return try receiveGrant(grant)
        case .grantCancel(let grantID, let matchID):
            return try receiveGrantCancel(grantID: grantID, matchID: matchID)
        case .draftReady, .grantAccepted, .grantCancelled, .unsupportedVersion:
            // Phone-side signals; the app layer acts on them.
            return []
        }
    }

    private func receiveManifest(_ manifest: MatchManifest) throws -> [JournalMessage] {
        guard manifest.schemaVersion <= JournalProtocol.schemaVersion else {
            return [.unsupportedVersion(JournalProtocol.schemaVersion)]
        }
        if let existing = journals[manifest.matchID] {
            // Same match: just say where we are.
            return existing.role == .mirror ? [.receipt(existing.receipt)] : []
        }
        var journal = MatchJournal.mirror(manifest)
        // Operations that arrived before their manifest.
        let waiting = inbox.filter { $0.matchID == manifest.matchID }
        if !waiting.isEmpty { try journal.ingest(waiting) }
        try commit(journal)
        if !waiting.isEmpty {
            inbox.removeAll { $0.matchID == manifest.matchID }
            try store.saveInbox(inbox)
        }
        return replies(for: journal)
    }

    private func receiveOperations(matchID: UUID, _ operations: [MatchOperation]) throws -> [JournalMessage] {
        guard var journal = journals[matchID] else {
            // Keep them (bounded) and ask for the manifest.
            let known = Set(inbox.map(\.eventID))
            let fresh = operations.filter { $0.matchID == matchID && !known.contains($0.eventID) }
            if !fresh.isEmpty, inbox.count + fresh.count <= Self.inboxLimit {
                let updated = inbox + fresh
                try store.saveInbox(updated)
                inbox = updated
            }
            return [.resend(matchID: matchID, fromSequence: 1, needsManifest: true)]
        }
        guard journal.role == .mirror else {
            // We own this match: nobody else may add to it.
            return []
        }
        let result = try journal.ingest(operations)
        if result.newlyCommitted > 0 || journal.buffered != journals[matchID]?.buffered
            || result.conflicts > 0 {
            try commit(journal)
        }
        return replies(for: journal)
    }

    /// A receipt, plus a resend request when something is missing.
    private func replies(for journal: MatchJournal) -> [JournalMessage] {
        var replies: [JournalMessage] = [.receipt(journal.receipt)]
        if !journal.buffered.isEmpty || (journal.expectedFinalSequence.map { journal.committedSequence < $0 } ?? false) {
            replies.append(.resend(matchID: journal.matchID, fromSequence: journal.committedSequence + 1, needsManifest: false))
        }
        return replies
    }

    // MARK: Drafts and grants (Watch side)

    private func receiveDraft(_ draft: MatchDraft) throws -> [JournalMessage] {
        // A match already under way keeps its setup.
        if journals[draft.matchID] == nil {
            if let existing = drafts[draft.matchID], existing.draftVersion >= draft.draftVersion {
                return [.draftReady(matchID: draft.matchID, draftVersion: existing.draftVersion)]
            }
            try store.save(draft)
            drafts[draft.matchID] = draft
        }
        return [.draftReady(matchID: draft.matchID, draftVersion: drafts[draft.matchID]?.draftVersion ?? draft.draftVersion)]
    }

    private func receiveGrant(_ grant: ScoringGrant) throws -> [JournalMessage] {
        if let matchID = acceptedGrants[grant.grantID], let journal = journals[matchID] {
            // A repeat (our acceptance was lost): same answer, no second owner.
            return [.grantAccepted(grantID: grant.grantID, matchID: matchID, authorityEpoch: journal.manifest.authorityEpoch)]
        }
        if let journal = journals[grant.matchID] {
            // The match exists under a different grant: never a second owner.
            return [.grantAccepted(grantID: journal.manifest.grantID ?? grant.grantID, matchID: grant.matchID,
                                   authorityEpoch: journal.manifest.authorityEpoch)]
        }
        if activeOwnedMatch() != nil {
            // One match on the wrist at a time; the phone can try again.
            return [.grantCancelled(grantID: grant.grantID, matchID: grant.matchID, accepted: false)]
        }
        var setup = grant.draft.setup
        setup.host = .watch
        let journal = try startMatch(setup: setup, accountScopeID: grant.draft.accountScopeID,
                                     wearerTeam: grant.draft.wearerTeam, role: .watch,
                                     authorityEpoch: grant.authorityEpoch, grantID: grant.grantID, at: grant.issuedAt)
        acceptedGrants[grant.grantID] = journal.matchID
        if drafts[grant.matchID] != nil {
            try store.deleteDraft(grant.matchID)
            drafts[grant.matchID] = nil
        }
        return [.grantAccepted(grantID: grant.grantID, matchID: journal.matchID, authorityEpoch: grant.authorityEpoch),
                .manifest(journal.manifest), .operations(matchID: journal.matchID, journal.operations)]
    }

    /// The phone wants scoring back. Only before the first rally: after
    /// that, two histories would exist.
    private func receiveGrantCancel(grantID: UUID, matchID: UUID) throws -> [JournalMessage] {
        guard let journal = journals[matchID], journal.manifest.grantID == grantID else {
            // Never accepted: nothing to undo.
            if drafts[matchID] != nil {
                try store.deleteDraft(matchID)
                drafts[matchID] = nil
            }
            return [.grantCancelled(grantID: grantID, matchID: matchID, accepted: true)]
        }
        if journal.status == .abandoned {
            return [.grantCancelled(grantID: grantID, matchID: matchID, accepted: true)]
        }
        guard journal.rallyEvents.isEmpty, !journal.status.isTerminal else {
            return [.grantCancelled(grantID: grantID, matchID: matchID, accepted: false)]
        }
        let closed = try perform(.abandoned, in: matchID)
        return [.grantCancelled(grantID: grantID, matchID: matchID, accepted: true),
                .operations(matchID: matchID, closed.unacknowledged)]
    }

    // MARK: Retention

    /// Removes closed matches the other device fully holds, older than
    /// `age`. Unconfirmed records are never removed.
    public func compact(olderThan age: TimeInterval, now: Date = Date()) throws {
        for journal in journals.values where journal.status.isTerminal
            && now.timeIntervalSince(journal.manifest.createdAt) > age
            && (journal.role == .mirror ? journal.isComplete : journal.isFullyAcknowledged) {
            try store.deleteJournal(journal.matchID)
            journals[journal.matchID] = nil
        }
    }

    // MARK: Saving

    /// Store first, memory second.
    private func commit(_ journal: MatchJournal) throws {
        try store.save(journal)
        journals[journal.matchID] = journal
    }
}
