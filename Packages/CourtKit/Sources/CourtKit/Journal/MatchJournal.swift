//
//  MatchJournal.swift
//  CourtKit
//
//  One match's append-only operation log on one device, plus what's known
//  about the other device. The owner appends; a mirror ingests. The score
//  is always a replay of the committed operations through the same CourtKit
//  engine, so both devices compute it identically.
//

import Foundation

public enum JournalError: Error, Equatable, Sendable {
    /// Only the owning device may append.
    case notOwner
    /// The match is finished or abandoned.
    case matchClosed
    /// Not allowed right now (a rally while paused, finish without a winner…).
    case invalidAction(String)
    /// An operation for a different match, owner or epoch.
    case foreign(String)
}

public struct MatchJournal: Codable, Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable {
        /// Appends operations (the scoring device).
        case owner
        /// Stores the owner's operations in order.
        case mirror
    }

    public enum Status: String, Codable, Sendable {
        case live, paused, finished, abandoned

        public var isTerminal: Bool { self == .finished || self == .abandoned }
    }

    public struct IngestResult: Equatable, Sendable {
        public var newlyCommitted: Int = 0
        public var duplicates: Int = 0
        public var conflicts: Int = 0
        /// First sequence still missing, when operations arrived past a gap.
        public var missingFrom: Int64?
    }

    public let manifest: MatchManifest
    public let role: Role
    /// Committed operations, sequences 1…n with no gaps.
    public private(set) var operations: [MatchOperation]
    /// Mirror only: operations that arrived past a gap, waiting for it to fill.
    public private(set) var buffered: [MatchOperation]
    /// Owner only: highest sequence the other device has confirmed saving.
    public private(set) var acknowledgedSequence: Int64
    /// The player closed the result screen. The record stays.
    public var isDismissed: Bool
    /// Operations whose sequence or event ID clashed with ones we hold.
    public private(set) var conflictCount: Int

    public var id: UUID { manifest.matchID }
    public var matchID: UUID { manifest.matchID }

    /// Most operations kept waiting behind a gap.
    public static let bufferLimit = 2_000

    // MARK: Creating

    /// A new match owned by this device, opened with its `started` operation.
    public static func owned(_ manifest: MatchManifest, startedAt: Date) -> MatchJournal {
        var journal = MatchJournal(manifest: manifest, role: .owner)
        let first = MatchOperation(accountScopeID: manifest.accountScopeID, matchID: manifest.matchID,
                                   ownerDeviceID: manifest.ownerDeviceID, authorityEpoch: manifest.authorityEpoch,
                                   sequence: 1, occurredAt: startedAt, payload: .started)
        journal.operations = [first]
        return journal
    }

    /// The other device's copy of a match.
    public static func mirror(_ manifest: MatchManifest) -> MatchJournal {
        MatchJournal(manifest: manifest, role: .mirror)
    }

    private init(manifest: MatchManifest, role: Role) {
        self.manifest = manifest
        self.role = role
        self.operations = []
        self.buffered = []
        self.acknowledgedSequence = 0
        self.isDismissed = false
        self.conflictCount = 0
    }

    // MARK: Reading

    public var committedSequence: Int64 { operations.last?.sequence ?? 0 }

    public var status: Status {
        var status = Status.live
        for operation in operations {
            switch operation.payload {
            case .paused: status = .paused
            case .resumed: status = .live
            case .finished: return .finished
            case .abandoned: return .abandoned
            default: break
            }
        }
        return status
    }

    /// Effective rallies after undos, oldest first, with the event that made each.
    public var rallyEvents: [(eventID: UUID, rally: Rally)] {
        var result: [(eventID: UUID, rally: Rally)] = []
        for operation in operations {
            switch operation.payload {
            case .rallyWon(let team):
                result.append((operation.eventID, Rally(winner: team, at: operation.occurredAt)))
            case .undo(let target):
                if let index = result.lastIndex(where: { $0.eventID == target }) { result.remove(at: index) }
            default:
                break
            }
        }
        return result
    }

    public var rallies: [Rally] { rallyEvents.map(\.rally) }

    /// The score, replayed through CourtKit.
    public var scorer: MatchScorer { MatchScorer(rules: manifest.setup.rules, rallies: rallies) }

    public var finishOperation: MatchOperation? {
        operations.last.flatMap { $0.payload.isTerminal ? $0 : nil }
    }

    /// The final sequence announced by a finish, even if it arrived early
    /// and is still waiting behind a gap.
    public var expectedFinalSequence: Int64? {
        for operation in operations + buffered {
            if case .finished(let final, _, _) = operation.payload { return final }
            if case .abandoned = operation.payload { return operation.sequence }
        }
        return nil
    }

    /// Mirror: every operation up to the finish is here.
    public var isComplete: Bool {
        guard status.isTerminal, let final = expectedFinalSequence else { return false }
        return committedSequence >= final
    }

    /// Owner: operations the other device hasn't confirmed.
    public var unacknowledged: [MatchOperation] {
        operations.filter { $0.sequence > acknowledgedSequence }
    }

    /// Owner: the other device holds the whole closed match.
    public var isFullyAcknowledged: Bool {
        status.isTerminal && acknowledgedSequence >= committedSequence
    }

    /// A short fingerprint of the rally log, for the finish operation.
    public static func checksum(_ rallies: [Rally]) -> String {
        // FNV-1a over the winner sequence: enough to catch a different replay.
        var hash: UInt64 = 0xcbf29ce484222325
        for rally in rallies {
            hash ^= UInt64(rally.winner.rawValue + 1)
            hash = hash &* 0x100000001b3
        }
        return String(rallies.count) + "-" + String(hash, radix: 16)
    }

    // MARK: Owner

    /// Appends an action. Returns the new operation; the journal is
    /// unchanged if it throws.
    @discardableResult
    public mutating func append(_ action: MatchOperationPayload, at date: Date) throws -> MatchOperation {
        guard role == .owner else { throw JournalError.notOwner }
        let current = status
        guard !current.isTerminal else { throw JournalError.matchClosed }
        let scorer = self.scorer
        var payload = action
        switch action {
        case .started:
            throw JournalError.invalidAction("already started")
        case .rallyWon:
            guard current == .live else { throw JournalError.invalidAction("paused") }
            guard !scorer.isFinished else { throw JournalError.invalidAction("match already has a winner") }
        case .undo:
            guard current == .live, let last = rallyEvents.last else { throw JournalError.invalidAction("nothing to undo") }
            payload = .undo(target: last.eventID)
        case .paused:
            guard current == .live else { throw JournalError.invalidAction("not live") }
        case .resumed:
            guard current == .paused else { throw JournalError.invalidAction("not paused") }
        case .finished:
            guard let winner = scorer.winner else { throw JournalError.invalidAction("no winner yet") }
            payload = .finished(finalSequence: committedSequence + 1, winner: winner, checksum: Self.checksum(rallies))
        case .abandoned:
            break
        }
        let operation = MatchOperation(accountScopeID: manifest.accountScopeID, matchID: manifest.matchID,
                                       ownerDeviceID: manifest.ownerDeviceID, authorityEpoch: manifest.authorityEpoch,
                                       sequence: committedSequence + 1, occurredAt: date, payload: payload)
        operations.append(operation)
        return operation
    }

    /// Owner: the other device confirmed saving up to `sequence`.
    public mutating func acknowledge(_ receipt: JournalReceipt) {
        guard receipt.matchID == matchID, receipt.authorityEpoch == manifest.authorityEpoch else { return }
        acknowledgedSequence = max(acknowledgedSequence, min(receipt.committedSequence, committedSequence))
    }

    /// Owner: operations from `sequence` on, for a resend request.
    public func operations(from sequence: Int64, limit: Int) -> [MatchOperation] {
        Array(operations.filter { $0.sequence >= sequence }.prefix(limit))
    }

    // MARK: Mirror

    /// Stores the owner's operations: duplicates are recognised, nothing is
    /// committed past a gap, and a different operation claiming a slot we
    /// already hold is counted as a conflict and never replaces it.
    @discardableResult
    public mutating func ingest(_ incoming: [MatchOperation]) throws -> IngestResult {
        guard role == .mirror else { throw JournalError.notOwner }
        var result = IngestResult()
        for operation in incoming {
            guard operation.matchID == matchID else { throw JournalError.foreign("match") }
            guard operation.ownerDeviceID == manifest.ownerDeviceID else { throw JournalError.foreign("owner") }
            // An operation from an older authority is stale; a newer one
            // needs a new manifest first.
            guard operation.authorityEpoch == manifest.authorityEpoch else {
                result.conflicts += 1
                continue
            }
            guard operation.sequence >= 1, operation.schemaVersion <= JournalProtocol.schemaVersion else {
                result.conflicts += 1
                continue
            }
            if operation.sequence <= committedSequence {
                if operations[Int(operation.sequence - 1)].isSameOperation(as: operation) {
                    result.duplicates += 1
                } else {
                    result.conflicts += 1
                }
                continue
            }
            if let waiting = buffered.first(where: { $0.sequence == operation.sequence }) {
                if waiting.isSameOperation(as: operation) { result.duplicates += 1 } else { result.conflicts += 1 }
                continue
            }
            // Nothing may follow a terminal operation.
            if let final = expectedFinalSequence, operation.sequence > final {
                result.conflicts += 1
                continue
            }
            guard buffered.count < Self.bufferLimit else { continue }
            buffered.append(operation)
        }
        // Commit whatever is now contiguous.
        buffered.sort { $0.sequence < $1.sequence }
        while let next = buffered.first, next.sequence == committedSequence + 1 {
            operations.append(buffered.removeFirst())
            result.newlyCommitted += 1
        }
        if !buffered.isEmpty { result.missingFrom = committedSequence + 1 }
        conflictCount += result.conflicts
        return result
    }

    /// Mirror: what to tell the owner.
    public var receipt: JournalReceipt {
        JournalReceipt(matchID: matchID, authorityEpoch: manifest.authorityEpoch,
                       committedSequence: committedSequence, isComplete: isComplete)
    }
}
