//
//  MatchOperation.swift
//  CourtKit
//
//  The match journal protocol for Watch-owned scoring (schema 2).
//
//  One device owns a match's scoring from the moment it starts. Every
//  accepted action is an immutable operation with a sequence number that
//  only ever goes up (undo and finish are operations too, so the sequence
//  never falls with the score). The owner saves each operation before it
//  shows success, then sends it. The other device stores operations in
//  order, never past a gap, and answers with a receipt for the highest
//  contiguous sequence it has saved. Lost receipts just cause harmless
//  resends; duplicates are recognised by event ID.
//
//  Timestamps describe when things happened, never their order.
//

import Foundation

// MARK: - Operations

public enum MatchOperationPayload: Hashable, Sendable {
    /// First operation of every match.
    case started
    /// A rally won by this team (not "a point": in side-out scoring a lost
    /// rally can change serve without scoring).
    case rallyWon(Team)
    /// Undoes the rally created by `target`.
    case undo(target: UUID)
    case paused
    case resumed
    /// Ordered, final operation of a completed match. `finalSequence` is
    /// this operation's own sequence; a receiver missing earlier operations
    /// knows to fetch them before treating the match as complete.
    case finished(finalSequence: Int64, winner: Team, checksum: String)
    /// Stopped without a result.
    case abandoned

    public var isTerminal: Bool {
        switch self {
        case .finished, .abandoned: return true
        default: return false
        }
    }
}

public struct MatchOperation: Hashable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let accountScopeID: UUID?
    public let matchID: UUID
    public let eventID: UUID
    public let ownerDeviceID: UUID
    public let authorityEpoch: Int64
    /// 1-based, contiguous, never reused.
    public let sequence: Int64
    public let occurredAt: Date
    public let payload: MatchOperationPayload

    public var id: UUID { eventID }

    public init(schemaVersion: Int = JournalProtocol.schemaVersion, accountScopeID: UUID?, matchID: UUID,
                eventID: UUID = UUID(), ownerDeviceID: UUID, authorityEpoch: Int64, sequence: Int64,
                occurredAt: Date, payload: MatchOperationPayload) {
        self.schemaVersion = schemaVersion
        self.accountScopeID = accountScopeID
        self.matchID = matchID
        self.eventID = eventID
        self.ownerDeviceID = ownerDeviceID
        self.authorityEpoch = authorityEpoch
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.payload = payload
    }

    /// Same identity and content (a duplicate delivery), as opposed to a
    /// different operation claiming the same slot.
    public func isSameOperation(as other: MatchOperation) -> Bool {
        eventID == other.eventID && sequence == other.sequence && payload == other.payload
            && matchID == other.matchID && authorityEpoch == other.authorityEpoch
    }
}

public enum JournalProtocol {
    /// Bump when the wire format changes incompatibly.
    public static let schemaVersion = 2
    /// Bump when CourtKit's scoring rules change in a way that could
    /// replay an old log differently.
    public static let engineVersion = 1
}

// MARK: - Manifest

/// Everything needed to replay a match: rules, lineup, who owns scoring.
public struct MatchManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var engineVersion: Int
    public var matchID: UUID { setup.matchID }
    /// The account the match belongs to; nil when scored signed out.
    public var accountScopeID: UUID?
    public var setup: MatchSetup
    /// The only device allowed to append operations.
    public var ownerDeviceID: UUID
    public var ownerRole: DeviceRole
    public var authorityEpoch: Int64
    /// The wearer's team, so "Us" and victory map to the right side.
    public var wearerTeam: Team?
    /// The grant that made this device the owner, if the phone set it up.
    public var grantID: UUID?
    public var createdAt: Date

    public init(setup: MatchSetup, accountScopeID: UUID?, ownerDeviceID: UUID, ownerRole: DeviceRole,
                authorityEpoch: Int64 = 1, wearerTeam: Team?, grantID: UUID? = nil, createdAt: Date = Date()) {
        self.schemaVersion = JournalProtocol.schemaVersion
        self.engineVersion = JournalProtocol.engineVersion
        self.accountScopeID = accountScopeID
        self.setup = setup
        self.ownerDeviceID = ownerDeviceID
        self.ownerRole = ownerRole
        self.authorityEpoch = authorityEpoch
        self.wearerTeam = wearerTeam
        self.grantID = grantID
        self.createdAt = createdAt
    }
}

// MARK: - Receipts, drafts and grants

/// "I have saved every operation up to `committedSequence`."
public struct JournalReceipt: Codable, Hashable, Sendable {
    public var matchID: UUID
    public var authorityEpoch: Int64
    public var committedSequence: Int64
    /// The receiver holds the whole match, finish included.
    public var isComplete: Bool

    public init(matchID: UUID, authorityEpoch: Int64, committedSequence: Int64, isComplete: Bool) {
        self.matchID = matchID
        self.authorityEpoch = authorityEpoch
        self.committedSequence = committedSequence
        self.isComplete = isComplete
    }
}

/// A match set up on the phone, waiting on the Watch.
public struct MatchDraft: Codable, Hashable, Sendable {
    public var setup: MatchSetup
    /// Goes up when the phone edits the draft; the Watch confirms a version.
    public var draftVersion: Int
    public var accountScopeID: UUID?
    public var wearerTeam: Team?
    public var matchID: UUID { setup.matchID }

    public init(setup: MatchSetup, draftVersion: Int = 1, accountScopeID: UUID?, wearerTeam: Team?) {
        self.setup = setup
        self.draftVersion = draftVersion
        self.accountScopeID = accountScopeID
        self.wearerTeam = wearerTeam
    }
}

/// The phone hands scoring of a draft to the Watch. Carries the draft, so
/// it never depends on an earlier message having arrived.
public struct ScoringGrant: Codable, Hashable, Sendable {
    public var grantID: UUID
    public var draft: MatchDraft
    public var authorityEpoch: Int64
    public var issuedAt: Date
    public var matchID: UUID { draft.matchID }

    public init(grantID: UUID = UUID(), draft: MatchDraft, authorityEpoch: Int64 = 1, issuedAt: Date = Date()) {
        self.grantID = grantID
        self.draft = draft
        self.authorityEpoch = authorityEpoch
        self.issuedAt = issuedAt
    }
}

// MARK: - Wire envelope

/// Everything the journal protocol sends between phone and Watch.
public enum JournalMessage: Hashable, Sendable {
    case manifest(MatchManifest)
    case operations(matchID: UUID, [MatchOperation])
    case receipt(JournalReceipt)
    /// "Send me this match from `fromSequence` (and its manifest if I lack it)."
    case resend(matchID: UUID, fromSequence: Int64, needsManifest: Bool)
    case draft(MatchDraft)
    case draftReady(matchID: UUID, draftVersion: Int)
    case grant(ScoringGrant)
    case grantAccepted(grantID: UUID, matchID: UUID, authorityEpoch: Int64)
    /// The phone takes a grant back (only honoured before any rally).
    case grantCancel(grantID: UUID, matchID: UUID)
    case grantCancelled(grantID: UUID, matchID: UUID, accepted: Bool)
    /// The sender speaks a newer schema; the receiver should ask for an update.
    case unsupportedVersion(Int)

    public var matchID: UUID? {
        switch self {
        case .manifest(let m): return m.matchID
        case .operations(let id, _), .resend(let id, _, _), .draftReady(let id, _),
             .grantAccepted(_, let id, _), .grantCancel(_, let id), .grantCancelled(_, let id, _):
            return id
        case .receipt(let r): return r.matchID
        case .draft(let d): return d.matchID
        case .grant(let g): return g.matchID
        case .unsupportedVersion: return nil
        }
    }
}

extension JournalMessage {
    /// Separate from schema 1 (`SyncMessage`), so both can travel together.
    public static let payloadKey = "courtkit.journal.v2"

    public var wcPayload: [String: Any] {
        guard let data = try? JSONEncoder.courtKit.encode(Envelope(version: JournalProtocol.schemaVersion, message: self)) else {
            return [:]
        }
        return [Self.payloadKey: data]
    }

    /// Decodes a WatchConnectivity dictionary. Malformed data yields nil;
    /// a newer schema yields `.unsupportedVersion` so the app can say so.
    public init?(wcPayload: [String: Any]) {
        guard let data = wcPayload[Self.payloadKey] as? Data else { return nil }
        guard let message = Self.decode(data) else { return nil }
        self = message
    }

    public static func decode(_ data: Data) -> JournalMessage? {
        struct VersionOnly: Decodable { let version: Int }
        guard let version = try? JSONDecoder.courtKit.decode(VersionOnly.self, from: data) else { return nil }
        if version.version > JournalProtocol.schemaVersion { return .unsupportedVersion(version.version) }
        return (try? JSONDecoder.courtKit.decode(Envelope.self, from: data))?.message
    }

    public var encoded: Data? {
        try? JSONEncoder.courtKit.encode(Envelope(version: JournalProtocol.schemaVersion, message: self))
    }

    /// Several messages in one batch (one `transferUserInfo`, not one per
    /// event), keyed so they never collide with schema 1 keys.
    public static func batchPayload(_ messages: [JournalMessage]) -> [String: Any] {
        let encoded = messages.compactMap(\.encoded)
        return encoded.isEmpty ? [:] : [batchKey: encoded]
    }

    public static let batchKey = "courtkit.journal.v2.batch"

    /// Every journal message in a WatchConnectivity dictionary.
    public static func messages(in payload: [String: Any]) -> [JournalMessage] {
        var result: [JournalMessage] = []
        if let single = JournalMessage(wcPayload: payload) { result.append(single) }
        if let batch = payload[batchKey] as? [Data] {
            result += batch.compactMap(decode)
        }
        return result
    }

    private struct Envelope: Codable {
        let version: Int
        let message: JournalMessage
    }
}

// MARK: - Codable

extension MatchOperationPayload: Codable {
    private enum CodingKeys: String, CodingKey { case type, team, target, finalSequence, winner, checksum }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "started": self = .started
        case "rallyWon": self = .rallyWon(try c.decode(Team.self, forKey: .team))
        case "undo": self = .undo(target: try c.decode(UUID.self, forKey: .target))
        case "paused": self = .paused
        case "resumed": self = .resumed
        case "finished":
            self = .finished(finalSequence: try c.decode(Int64.self, forKey: .finalSequence),
                             winner: try c.decode(Team.self, forKey: .winner),
                             checksum: try c.decode(String.self, forKey: .checksum))
        case "abandoned": self = .abandoned
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown operation \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .started: try c.encode("started", forKey: .type)
        case .rallyWon(let team):
            try c.encode("rallyWon", forKey: .type)
            try c.encode(team, forKey: .team)
        case .undo(let target):
            try c.encode("undo", forKey: .type)
            try c.encode(target, forKey: .target)
        case .paused: try c.encode("paused", forKey: .type)
        case .resumed: try c.encode("resumed", forKey: .type)
        case .finished(let finalSequence, let winner, let checksum):
            try c.encode("finished", forKey: .type)
            try c.encode(finalSequence, forKey: .finalSequence)
            try c.encode(winner, forKey: .winner)
            try c.encode(checksum, forKey: .checksum)
        case .abandoned: try c.encode("abandoned", forKey: .type)
        }
    }
}

extension MatchOperation: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "v", accountScopeID = "acct", matchID = "m", eventID = "id", ownerDeviceID = "own"
        case authorityEpoch = "ep", sequence = "seq", occurredAt = "at", payload = "p"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        accountScopeID = try c.decodeIfPresent(UUID.self, forKey: .accountScopeID)
        matchID = try c.decode(UUID.self, forKey: .matchID)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        ownerDeviceID = try c.decode(UUID.self, forKey: .ownerDeviceID)
        authorityEpoch = try c.decode(Int64.self, forKey: .authorityEpoch)
        sequence = try c.decode(Int64.self, forKey: .sequence)
        occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        payload = try c.decode(MatchOperationPayload.self, forKey: .payload)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(accountScopeID, forKey: .accountScopeID)
        try c.encode(matchID, forKey: .matchID)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(ownerDeviceID, forKey: .ownerDeviceID)
        try c.encode(authorityEpoch, forKey: .authorityEpoch)
        try c.encode(sequence, forKey: .sequence)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encode(payload, forKey: .payload)
    }
}

extension JournalMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, manifest, matchID, operations, receipt, fromSequence, needsManifest, draft, draftVersion
        case grant, grantID, authorityEpoch, accepted, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "manifest": self = .manifest(try c.decode(MatchManifest.self, forKey: .manifest))
        case "operations":
            self = .operations(matchID: try c.decode(UUID.self, forKey: .matchID),
                               try c.decode([MatchOperation].self, forKey: .operations))
        case "receipt": self = .receipt(try c.decode(JournalReceipt.self, forKey: .receipt))
        case "resend":
            self = .resend(matchID: try c.decode(UUID.self, forKey: .matchID),
                           fromSequence: try c.decode(Int64.self, forKey: .fromSequence),
                           needsManifest: try c.decodeIfPresent(Bool.self, forKey: .needsManifest) ?? false)
        case "draft": self = .draft(try c.decode(MatchDraft.self, forKey: .draft))
        case "draftReady":
            self = .draftReady(matchID: try c.decode(UUID.self, forKey: .matchID),
                               draftVersion: try c.decode(Int.self, forKey: .draftVersion))
        case "grant": self = .grant(try c.decode(ScoringGrant.self, forKey: .grant))
        case "grantAccepted":
            self = .grantAccepted(grantID: try c.decode(UUID.self, forKey: .grantID),
                                  matchID: try c.decode(UUID.self, forKey: .matchID),
                                  authorityEpoch: try c.decode(Int64.self, forKey: .authorityEpoch))
        case "grantCancel":
            self = .grantCancel(grantID: try c.decode(UUID.self, forKey: .grantID),
                                matchID: try c.decode(UUID.self, forKey: .matchID))
        case "grantCancelled":
            self = .grantCancelled(grantID: try c.decode(UUID.self, forKey: .grantID),
                                   matchID: try c.decode(UUID.self, forKey: .matchID),
                                   accepted: try c.decode(Bool.self, forKey: .accepted))
        case "unsupportedVersion": self = .unsupportedVersion(try c.decode(Int.self, forKey: .version))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown message \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manifest(let m):
            try c.encode("manifest", forKey: .type)
            try c.encode(m, forKey: .manifest)
        case .operations(let id, let ops):
            try c.encode("operations", forKey: .type)
            try c.encode(id, forKey: .matchID)
            try c.encode(ops, forKey: .operations)
        case .receipt(let r):
            try c.encode("receipt", forKey: .type)
            try c.encode(r, forKey: .receipt)
        case .resend(let id, let from, let needsManifest):
            try c.encode("resend", forKey: .type)
            try c.encode(id, forKey: .matchID)
            try c.encode(from, forKey: .fromSequence)
            try c.encode(needsManifest, forKey: .needsManifest)
        case .draft(let d):
            try c.encode("draft", forKey: .type)
            try c.encode(d, forKey: .draft)
        case .draftReady(let id, let version):
            try c.encode("draftReady", forKey: .type)
            try c.encode(id, forKey: .matchID)
            try c.encode(version, forKey: .draftVersion)
        case .grant(let g):
            try c.encode("grant", forKey: .type)
            try c.encode(g, forKey: .grant)
        case .grantAccepted(let grantID, let id, let epoch):
            try c.encode("grantAccepted", forKey: .type)
            try c.encode(grantID, forKey: .grantID)
            try c.encode(id, forKey: .matchID)
            try c.encode(epoch, forKey: .authorityEpoch)
        case .grantCancel(let grantID, let id):
            try c.encode("grantCancel", forKey: .type)
            try c.encode(grantID, forKey: .grantID)
            try c.encode(id, forKey: .matchID)
        case .grantCancelled(let grantID, let id, let accepted):
            try c.encode("grantCancelled", forKey: .type)
            try c.encode(grantID, forKey: .grantID)
            try c.encode(id, forKey: .matchID)
            try c.encode(accepted, forKey: .accepted)
        case .unsupportedVersion(let version):
            try c.encode("unsupportedVersion", forKey: .type)
            try c.encode(version, forKey: .version)
        }
    }
}
