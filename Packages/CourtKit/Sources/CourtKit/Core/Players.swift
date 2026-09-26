//
//  Players.swift
//  CourtKit
//
//  A player is always an ID. The display name is presentation only and can
//  change (or be claimed later) without rewriting any match history.
//

import Foundation

public struct PlayerID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

public enum PlayerKind: String, Codable, Hashable, Sendable {
    /// Someone with (or who will have) an account. The device owner is a user.
    case user
    /// Added on the spot at the court. Can be claimed by a user later.
    case guest
}

public struct PlayerRef: Identifiable, Hashable, Codable, Sendable {
    public var id: PlayerID
    public var kind: PlayerKind
    public var displayName: String

    public init(id: PlayerID = PlayerID(), kind: PlayerKind, displayName: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
    }

    public static func guest(_ name: String) -> PlayerRef {
        PlayerRef(kind: .guest, displayName: name)
    }

    /// First word of the display name, for tight spaces like the Watch.
    public var shortName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }
}

/// A specific player position: team plus index into that team's roster.
public struct PlayerSlot: Hashable, Codable, Sendable {
    public var team: Team
    public var index: Int

    public init(team: Team, index: Int) {
        self.team = team
        self.index = index
    }
}

/// Who is on each side of the net for one match.
public struct Lineup: Hashable, Codable, Sendable {
    public var teams: TeamPair<[PlayerRef]>

    public init(teams: TeamPair<[PlayerRef]>) {
        self.teams = teams
    }

    public init(teamA: [PlayerRef], teamB: [PlayerRef]) {
        self.teams = TeamPair(a: teamA, b: teamB)
    }

    public var isDoubles: Bool { teams.a.count > 1 || teams.b.count > 1 }

    public var allPlayers: [PlayerRef] { teams.a + teams.b }

    public func team(of player: PlayerID) -> Team? {
        if teams.a.contains(where: { $0.id == player }) { return .a }
        if teams.b.contains(where: { $0.id == player }) { return .b }
        return nil
    }

    public func player(at slot: PlayerSlot) -> PlayerRef? {
        let roster = teams[slot.team]
        guard roster.indices.contains(slot.index) else { return nil }
        return roster[slot.index]
    }

    /// "SAM / PRIYA" style label for a side.
    public func name(of team: Team, separator: String = " / ") -> String {
        let names = teams[team].map(\.displayName).filter { !$0.isEmpty }
        return names.isEmpty ? (team == .a ? "Team A" : "Team B") : names.joined(separator: separator)
    }

    public func shortName(of team: Team) -> String {
        let names = teams[team].map(\.shortName).filter { !$0.isEmpty }
        return names.isEmpty ? (team == .a ? "A" : "B") : names.joined(separator: "/")
    }
}
