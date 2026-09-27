//
//  Team.swift
//  CourtKit
//

import Foundation

/// One side of the net. Every engine, log entry and sync message speaks in
/// teams, never in player names.
public enum Team: Int, Codable, CaseIterable, Hashable, Sendable {
    case a = 0
    case b = 1

    public var opponent: Team { self == .a ? .b : .a }

    /// Single-letter code used in compact wire formats and test transcripts.
    public var code: Character { self == .a ? "A" : "B" }

    public init?(code: Character) {
        switch code {
        case "A", "a": self = .a
        case "B", "b": self = .b
        default: return nil
        }
    }
}

/// A value for each team. Subscript by `Team` instead of juggling
/// `player1Points` / `player2Points` pairs.
public struct TeamPair<Value> {
    public var a: Value
    public var b: Value

    public init(a: Value, b: Value) {
        self.a = a
        self.b = b
    }

    public init(repeating value: Value) {
        self.a = value
        self.b = value
    }

    public subscript(team: Team) -> Value {
        get { team == .a ? a : b }
        set {
            if team == .a { a = newValue } else { b = newValue }
        }
    }

    public func map<T>(_ transform: (Value) throws -> T) rethrows -> TeamPair<T> {
        TeamPair<T>(a: try transform(a), b: try transform(b))
    }

    /// The same pair seen from the other side of the net.
    public var swapped: TeamPair<Value> { TeamPair(a: b, b: a) }
}

extension TeamPair: Equatable where Value: Equatable {}
extension TeamPair: Hashable where Value: Hashable {}
extension TeamPair: Sendable where Value: Sendable {}
extension TeamPair: Codable where Value: Codable {}

extension TeamPair where Value == Int {
    public static var zero: TeamPair<Int> { TeamPair(a: 0, b: 0) }

    /// The team with the higher value, or `nil` on a tie.
    public var leader: Team? {
        if a == b { return nil }
        return a > b ? .a : .b
    }

    public var total: Int { a + b }
}

/// The side of the court a player serves from, as seen by the server.
public enum CourtSide: String, Codable, Hashable, Sendable {
    /// Even court in pickleball, deuce court in padel.
    case right
    /// Odd court in pickleball, advantage court in padel.
    case left
}
