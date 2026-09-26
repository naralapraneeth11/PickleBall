//
//  SyncMessage.swift
//  CourtKit
//
//  Phone ⇄ Watch wire protocol. Devices exchange rally events
//  ("team A won rally 37"), never score snapshots, so both sides replay the
//  same log through the same engine and cannot disagree about the score.
//
//  The device that starts a match is its host and owns the authoritative
//  log. The other device is a client: it applies its own taps immediately
//  (optimistically) and sends them to the host as intents. The host accepts
//  an intent only if it was made on top of the host's current log, so two
//  people tapping the same rally on two devices can never double count it.
//

import Foundation

public enum DeviceRole: String, Codable, Hashable, Sendable {
    case phone
    case watch
}

public struct MatchSetup: Codable, Hashable, Sendable, Identifiable {
    public var matchID: UUID
    public var rules: MatchRules
    public var lineup: Lineup
    public var startedAt: Date
    /// Device holding the authoritative rally log.
    public var host: DeviceRole
    /// Set when the match belongs to a tournament fixture.
    public var tournamentMatchID: UUID?

    public var id: UUID { matchID }

    public init(
        matchID: UUID = UUID(),
        rules: MatchRules,
        lineup: Lineup,
        startedAt: Date = Date(),
        host: DeviceRole,
        tournamentMatchID: UUID? = nil
    ) {
        self.matchID = matchID
        self.rules = rules
        self.lineup = lineup
        self.startedAt = startedAt
        self.host = host
        self.tournamentMatchID = tournamentMatchID
    }
}

public struct RallyIntent: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case rally(Team, at: Date)
        /// Undo rally number `sequence` (1-based), which must be the last.
        case undo(sequence: Int)
    }

    public var id: UUID
    public var kind: Kind
    /// Number of rallies in the client's view when the intent was made.
    public var basedOn: Int

    public init(id: UUID = UUID(), kind: Kind, basedOn: Int) {
        self.id = id
        self.kind = kind
        self.basedOn = basedOn
    }
}

public struct RallyEvent: Codable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Rally number `sequence` was won by the team.
        case rally(Team, at: Date)
        /// Rally number `sequence` was removed.
        case undo
    }

    /// 1-based rally number this event creates or removes.
    public var sequence: Int
    public var kind: Kind
    /// Echo of the client intent this event applies, if any.
    public var intentID: UUID?

    public init(sequence: Int, kind: Kind, intentID: UUID? = nil) {
        self.sequence = sequence
        self.kind = kind
        self.intentID = intentID
    }
}

public enum EndReason: String, Codable, Hashable, Sendable {
    /// The engine produced a winner.
    case completed
    /// Stopped early; not saved as a result.
    case abandoned
    /// Paused to be resumed later.
    case parked
}

/// Authoritative full log. Sent as application context so a device that
/// was asleep or out of range can bootstrap from a single message.
public struct LogSnapshot: Hashable, Sendable {
    public var setup: MatchSetup
    public var rallies: [Rally]
    /// Recently applied intent IDs, so clients can retire acknowledged taps.
    public var appliedIntentIDs: [UUID]
    public var ended: EndReason?

    public init(setup: MatchSetup, rallies: [Rally], appliedIntentIDs: [UUID] = [], ended: EndReason? = nil) {
        self.setup = setup
        self.rallies = rallies
        self.appliedIntentIDs = appliedIntentIDs
        self.ended = ended
    }
}

public enum SyncMessage: Hashable, Sendable {
    case matchStarted(LogSnapshot)
    case intent(matchID: UUID, RallyIntent)
    case intentRejected(matchID: UUID, intentID: UUID)
    case event(matchID: UUID, RallyEvent)
    case log(LogSnapshot)
    case logRequest(matchID: UUID)
    case matchEnded(matchID: UUID, EndReason)
    /// The phone's active sport, so the Watch follows the phone's mode.
    case sportMode(Sport)

    public var matchID: UUID? {
        switch self {
        case .matchStarted(let snapshot), .log(let snapshot): return snapshot.setup.matchID
        case .intent(let id, _), .intentRejected(let id, _), .event(let id, _),
             .logRequest(let id), .matchEnded(let id, _):
            return id
        case .sportMode: return nil
        }
    }
}

// MARK: - WatchConnectivity payloads

extension SyncMessage {
    public static let payloadKey = "courtkit.v1"

    /// Property-list dictionary for `WCSession` APIs.
    public var wcPayload: [String: Any] {
        guard let data = try? JSONEncoder.courtKit.encode(self) else { return [:] }
        return [Self.payloadKey: data]
    }

    public init?(wcPayload: [String: Any]) {
        guard let data = wcPayload[Self.payloadKey] as? Data,
              let message = try? JSONDecoder.courtKit.decode(SyncMessage.self, from: data) else {
            return nil
        }
        self = message
    }
}

extension JSONEncoder {
    static var courtKit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var courtKit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

// MARK: - Codable

extension SyncMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, matchID, snapshot, intent, intentID, event, reason, sport
    }

    private enum MessageType: String, Codable {
        case matchStarted, intent, intentRejected, event, log, logRequest, matchEnded, sportMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(MessageType.self, forKey: .type) {
        case .matchStarted: self = .matchStarted(try c.decode(LogSnapshot.self, forKey: .snapshot))
        case .log: self = .log(try c.decode(LogSnapshot.self, forKey: .snapshot))
        case .intent:
            self = .intent(matchID: try c.decode(UUID.self, forKey: .matchID),
                           try c.decode(RallyIntent.self, forKey: .intent))
        case .intentRejected:
            self = .intentRejected(matchID: try c.decode(UUID.self, forKey: .matchID),
                                   intentID: try c.decode(UUID.self, forKey: .intentID))
        case .event:
            self = .event(matchID: try c.decode(UUID.self, forKey: .matchID),
                          try c.decode(RallyEvent.self, forKey: .event))
        case .logRequest:
            self = .logRequest(matchID: try c.decode(UUID.self, forKey: .matchID))
        case .matchEnded:
            self = .matchEnded(matchID: try c.decode(UUID.self, forKey: .matchID),
                               try c.decode(EndReason.self, forKey: .reason))
        case .sportMode:
            self = .sportMode(try c.decode(Sport.self, forKey: .sport))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .matchStarted(let snapshot):
            try c.encode(MessageType.matchStarted, forKey: .type)
            try c.encode(snapshot, forKey: .snapshot)
        case .log(let snapshot):
            try c.encode(MessageType.log, forKey: .type)
            try c.encode(snapshot, forKey: .snapshot)
        case .intent(let matchID, let intent):
            try c.encode(MessageType.intent, forKey: .type)
            try c.encode(matchID, forKey: .matchID)
            try c.encode(intent, forKey: .intent)
        case .intentRejected(let matchID, let intentID):
            try c.encode(MessageType.intentRejected, forKey: .type)
            try c.encode(matchID, forKey: .matchID)
            try c.encode(intentID, forKey: .intentID)
        case .event(let matchID, let event):
            try c.encode(MessageType.event, forKey: .type)
            try c.encode(matchID, forKey: .matchID)
            try c.encode(event, forKey: .event)
        case .logRequest(let matchID):
            try c.encode(MessageType.logRequest, forKey: .type)
            try c.encode(matchID, forKey: .matchID)
        case .matchEnded(let matchID, let reason):
            try c.encode(MessageType.matchEnded, forKey: .type)
            try c.encode(matchID, forKey: .matchID)
            try c.encode(reason, forKey: .reason)
        case .sportMode(let sport):
            try c.encode(MessageType.sportMode, forKey: .type)
            try c.encode(sport, forKey: .sport)
        }
    }
}

extension RallyIntent.Kind: Codable {
    private enum CodingKeys: String, CodingKey { case type, team, at, sequence }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decode(String.self, forKey: .type) == "undo" {
            self = .undo(sequence: try c.decode(Int.self, forKey: .sequence))
        } else {
            self = .rally(try c.decode(Team.self, forKey: .team), at: try c.decode(Date.self, forKey: .at))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rally(let team, let at):
            try c.encode("rally", forKey: .type)
            try c.encode(team, forKey: .team)
            try c.encode(at, forKey: .at)
        case .undo(let sequence):
            try c.encode("undo", forKey: .type)
            try c.encode(sequence, forKey: .sequence)
        }
    }
}

extension RallyEvent.Kind: Codable {
    private enum CodingKeys: String, CodingKey { case type, team, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decode(String.self, forKey: .type) == "undo" {
            self = .undo
        } else {
            self = .rally(try c.decode(Team.self, forKey: .team), at: try c.decode(Date.self, forKey: .at))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rally(let team, let at):
            try c.encode("rally", forKey: .type)
            try c.encode(team, forKey: .team)
            try c.encode(at, forKey: .at)
        case .undo:
            try c.encode("undo", forKey: .type)
        }
    }
}

extension LogSnapshot: Codable {
    // Rallies are packed as a winner string ("ABBA…") plus offsets from the
    // match start, which keeps a 300-rally log to a couple of kilobytes.
    private enum CodingKeys: String, CodingKey { case setup, winners, offsets, intents, ended }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setup = try c.decode(MatchSetup.self, forKey: .setup)
        let winners = try c.decode(String.self, forKey: .winners)
        let offsets = try c.decode([Double].self, forKey: .offsets)
        guard winners.count == offsets.count else {
            throw DecodingError.dataCorruptedError(forKey: .offsets, in: c,
                                                   debugDescription: "winners/offsets length mismatch")
        }
        var rallies: [Rally] = []
        rallies.reserveCapacity(offsets.count)
        for (code, offset) in zip(winners, offsets) {
            guard let team = Team(code: code) else {
                throw DecodingError.dataCorruptedError(forKey: .winners, in: c,
                                                       debugDescription: "invalid team code \(code)")
            }
            rallies.append(Rally(winner: team, at: setup.startedAt.addingTimeInterval(offset)))
        }
        self.rallies = rallies
        appliedIntentIDs = try c.decodeIfPresent([UUID].self, forKey: .intents) ?? []
        ended = try c.decodeIfPresent(EndReason.self, forKey: .ended)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(setup, forKey: .setup)
        try c.encode(String(rallies.map(\.winner.code)), forKey: .winners)
        try c.encode(rallies.map { $0.at.timeIntervalSince(setup.startedAt) }, forKey: .offsets)
        if !appliedIntentIDs.isEmpty { try c.encode(appliedIntentIDs, forKey: .intents) }
        try c.encodeIfPresent(ended, forKey: .ended)
    }
}
