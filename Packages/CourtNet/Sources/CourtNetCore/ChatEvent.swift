//
//  ChatEvent.swift
//  CourtNetCore
//
//  Event messages in friend and squad chats: results, belt changes, call
//  outs, Replays, squad news. The server writes most of them inside the
//  RPC that caused them; belt events are derived on the confirming phone
//  and passed along. Unknown types from a newer server decode as
//  `.unknown` so old app versions never fail on a new event.
//

import Foundation
import CourtKit

public enum ChatEvent: Hashable, Sendable, Codable {
    case result(matchID: UUID)
    case belt(BeltEvent)
    case callOut(callOutID: UUID, by: UUID)
    case replay(replayID: UUID, by: UUID)
    case joined(userID: UUID)
    case tournamentCreated(tournamentID: UUID)
    case champion(tournamentID: UUID, champions: [UUID])
    case unknown(type: String)

    enum CodingKeys: String, CodingKey {
        case type
        case matchID = "match_id"
        case event
        case callOutID = "callout_id"
        case replayID = "replay_id"
        case by
        case userID = "user_id"
        case tournamentID = "tournament_id"
        case champions
    }

    public var type: String {
        switch self {
        case .result: return "result"
        case .belt: return "belt"
        case .callOut: return "callout"
        case .replay: return "replay"
        case .joined: return "joined"
        case .tournamentCreated: return "tournament_created"
        case .champion: return "champion"
        case .unknown(let type): return type
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "result": self = .result(matchID: try c.decode(UUID.self, forKey: .matchID))
        case "belt": self = .belt(try c.decode(BeltEvent.self, forKey: .event))
        case "callout": self = .callOut(callOutID: try c.decode(UUID.self, forKey: .callOutID), by: try c.decode(UUID.self, forKey: .by))
        case "replay": self = .replay(replayID: try c.decode(UUID.self, forKey: .replayID), by: try c.decode(UUID.self, forKey: .by))
        case "joined": self = .joined(userID: try c.decode(UUID.self, forKey: .userID))
        case "tournament_created": self = .tournamentCreated(tournamentID: try c.decode(UUID.self, forKey: .tournamentID))
        case "champion":
            self = .champion(tournamentID: try c.decode(UUID.self, forKey: .tournamentID),
                             champions: try c.decode([UUID].self, forKey: .champions))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        switch self {
        case .result(let matchID): try c.encode(matchID, forKey: .matchID)
        case .belt(let event):
            try c.encode(event, forKey: .event)
            try c.encode(event.matchID, forKey: .matchID)
        case .callOut(let id, let by):
            try c.encode(id, forKey: .callOutID)
            try c.encode(by, forKey: .by)
        case .replay(let id, let by):
            try c.encode(id, forKey: .replayID)
            try c.encode(by, forKey: .by)
        case .joined(let userID): try c.encode(userID, forKey: .userID)
        case .tournamentCreated(let id): try c.encode(id, forKey: .tournamentID)
        case .champion(let id, let champions):
            try c.encode(id, forKey: .tournamentID)
            try c.encode(champions, forKey: .champions)
        case .unknown: break
        }
    }
}
