//
//  CallOut.swift
//  CourtKit
//
//  A challenge to a friend or a pair: sport, format, and optionally when and
//  where. The other side accepts, counters or declines; counters bounce
//  until someone accepts or declines. A confirmed result between the right
//  players closes it and posts to chat.
//
//  The server runs the same rules (respond_callout); this copy lets the app
//  show only the moves that are legal and update instantly while offline.
//

import Foundation

public struct CallOut: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case accepted
        case countered
        case declined
        case completed
        case cancelled

        /// Still waiting on a yes or no.
        public var isOpen: Bool { self == .pending || self == .countered }
        /// Agreed or still being negotiated: shows under "Call outs waiting".
        public var isActive: Bool { isOpen || self == .accepted }
    }

    /// When and where. Both optional: "Singles, first to 11" is a call out.
    public struct Terms: Hashable, Codable, Sendable {
        public var proposedAt: Date?
        public var court: CourtTag?

        public init(proposedAt: Date? = nil, court: CourtTag? = nil) {
            self.proposedAt = proposedAt
            self.court = court
        }
    }

    public enum Move: Hashable, Sendable {
        case accept
        case counter(Terms)
        case decline
        case cancel

        public var kind: MoveKind {
            switch self {
            case .accept: return .accept
            case .counter: return .counter
            case .decline: return .decline
            case .cancel: return .cancel
            }
        }
    }

    public enum MoveKind: String, Hashable, Sendable, CaseIterable {
        case accept, counter, decline, cancel
    }

    public enum MoveError: Error, Hashable, Sendable {
        case closed
        case notInCallOut
        case notYourTurn
        case onlyChallengerCancels
    }

    public let id: UUID
    public let createdBy: PlayerID
    public let challengers: [PlayerID]
    public let challenged: [PlayerID]
    public let sport: Sport
    public let rules: MatchRules
    public let squadID: UUID?
    public let createdAt: Date
    public private(set) var terms: Terms
    public private(set) var counter: Terms?
    public private(set) var counterBy: PlayerID?
    public private(set) var status: Status
    public private(set) var matchID: UUID?

    public init(
        id: UUID = UUID(),
        createdBy: PlayerID,
        challengers: [PlayerID],
        challenged: [PlayerID],
        rules: MatchRules,
        terms: Terms = Terms(),
        squadID: UUID? = nil,
        createdAt: Date = Date(),
        status: Status = .pending,
        counter: Terms? = nil,
        counterBy: PlayerID? = nil,
        matchID: UUID? = nil
    ) {
        self.id = id
        self.createdBy = createdBy
        self.challengers = challengers
        self.challenged = challenged
        self.sport = rules.sport
        self.rules = rules
        self.terms = terms
        self.squadID = squadID
        self.createdAt = createdAt
        self.status = status
        self.counter = counter
        self.counterBy = counterBy
        self.matchID = matchID
    }

    public var isDoubles: Bool { challengers.count > 1 }

    public func involves(_ player: PlayerID) -> Bool {
        challengers.contains(player) || challenged.contains(player)
    }

    /// Whose move it is: the challenged side first, then whoever didn't make
    /// the last counter.
    public func isTurn(of player: PlayerID) -> Bool {
        guard status.isOpen, involves(player) else { return false }
        switch status {
        case .pending: return challenged.contains(player)
        case .countered:
            guard let counterBy else { return false }
            let counterSide = challengers.contains(counterBy) ? challengers : challenged
            return !counterSide.contains(player)
        default: return false
        }
    }

    /// The moves `player` can make right now, in button order.
    public func moves(for player: PlayerID) -> [MoveKind] {
        var moves: [MoveKind] = []
        if isTurn(of: player) { moves += [.accept, .counter, .decline] }
        if status.isActive, player == createdBy { moves.append(.cancel) }
        return moves
    }

    public mutating func apply(_ move: Move, by player: PlayerID) throws {
        guard status.isActive else { throw MoveError.closed }
        guard involves(player) else { throw MoveError.notInCallOut }

        if case .cancel = move {
            guard player == createdBy else { throw MoveError.onlyChallengerCancels }
            status = .cancelled
            return
        }
        guard status.isOpen else { throw MoveError.closed }
        guard isTurn(of: player) else { throw MoveError.notYourTurn }

        switch move {
        case .accept:
            if let counter {
                terms = Terms(proposedAt: counter.proposedAt ?? terms.proposedAt, court: counter.court ?? terms.court)
            }
            status = .accepted
        case .counter(let offer):
            counter = offer
            counterBy = player
            status = .countered
        case .decline:
            status = .declined
        case .cancel:
            break
        }
    }

    /// True when a result between exactly these players settles the call out.
    public func isSettled(by lineup: Lineup) -> Bool {
        let a = Set(lineup.teams.a.map(\.id)), b = Set(lineup.teams.b.map(\.id))
        let x = Set(challengers), y = Set(challenged)
        return (a == x && b == y) || (a == y && b == x)
    }

    /// Closes the call out with the confirmed match that settled it.
    public mutating func complete(with matchID: UUID) {
        guard status.isActive else { return }
        self.matchID = matchID
        status = .completed
    }

    /// The terms on the table right now (a pending counter wins).
    public var currentTerms: Terms {
        guard status == .countered, let counter else { return terms }
        return Terms(proposedAt: counter.proposedAt ?? terms.proposedAt, court: counter.court ?? terms.court)
    }
}
