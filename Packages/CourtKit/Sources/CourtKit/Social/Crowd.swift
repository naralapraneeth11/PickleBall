//
//  Crowd.swift
//  CourtKit
//
//  Crowd taps: friends following a live Watch-scored match tap to send a
//  haptic chant to the players' wrists. Taps also fill a crowd meter the
//  players see between points. Each squad can have a signature chant only
//  its members can send.
//
//  The Watch plays chants politely: never during a rally-heavy burst, at
//  most one every few seconds, so a busy crowd never gets in the way.
//

import Foundation

public struct Chant: Identifiable, Hashable, Codable, Sendable {
    public struct Beat: Hashable, Codable, Sendable {
        /// Seconds from the start of the chant.
        public var at: Double
        /// 0…1. The Watch maps this to a lighter or stronger haptic.
        public var strength: Double

        public init(at: Double, strength: Double = 1) {
            self.at = at
            self.strength = strength
        }
    }

    public static let maxBeats = 10
    public static let maxDuration: Double = 3

    public var id: String
    public var name: String
    public private(set) var beats: [Beat]

    /// Beats are sorted, clamped to 0…3 s and 0…1 strength, and capped at
    /// ten so no chant can buzz a wrist for long.
    public init(id: String, name: String, beats: [Beat]) {
        self.id = id
        self.name = name
        self.beats = beats
            .map { Beat(at: min(max($0.at, 0), Self.maxDuration), strength: min(max($0.strength, 0), 1)) }
            .sorted { $0.at < $1.at }
            .prefix(Self.maxBeats)
            .map { $0 }
    }

    public var duration: Double { beats.last?.at ?? 0 }

    public static let letsGo = Chant(id: "lets-go", name: "Let’s go!", beats: [
        Beat(at: 0), Beat(at: 0.25), Beat(at: 0.75, strength: 0.6), Beat(at: 1.0, strength: 0.6), Beat(at: 1.25, strength: 0.6)
    ])
    public static let clapClap = Chant(id: "clap-clap", name: "Clap clap", beats: [
        Beat(at: 0), Beat(at: 0.3)
    ])
    public static let bigPoint = Chant(id: "big-point", name: "Big point", beats: [
        Beat(at: 0, strength: 0.4), Beat(at: 0.2, strength: 0.7), Beat(at: 0.4, strength: 1)
    ])
    public static let dinkDink = Chant(id: "dink-dink", name: "Dink dink", beats: [
        Beat(at: 0, strength: 0.5), Beat(at: 0.15, strength: 0.5), Beat(at: 0.5, strength: 0.5), Beat(at: 0.65, strength: 0.5)
    ])

    public static let presets: [Chant] = [letsGo, clapClap, bigPoint, dinkDink]

    public static func preset(id: String) -> Chant? { presets.first { $0.id == id } }

    /// A squad's signature chant, as stored in `squads.signature_chant`.
    public static func signature(squadName: String, beats: [Beat]) -> Chant {
        Chant(id: "squad", name: squadName, beats: beats)
    }
}

/// One tap from someone in the crowd.
public struct CrowdTap: Hashable, Codable, Sendable {
    public var matchID: UUID
    public var from: PlayerID
    public var fromName: String
    /// A preset id, or "squad" for the sender's squad chant.
    public var chantID: String
    public var at: Date

    public init(matchID: UUID, from: PlayerID, fromName: String, chantID: String, at: Date = Date()) {
        self.matchID = matchID
        self.from = from
        self.fromName = fromName
        self.chantID = chantID
        self.at = at
    }
}

/// Crowd noise as a 0…1 level: every tap adds energy that fades with a
/// 20-second half-life. Ten taps in a few seconds is a roar.
public struct CrowdMeter: Hashable, Sendable {
    public static let halfLife: TimeInterval = 20
    /// Energy at which the meter reads about 63%.
    public static let scale: Double = 6

    private var energy: Double = 0
    private var updatedAt: Date?

    public init() {}

    public mutating func add(at date: Date, weight: Double = 1) {
        energy = energy(at: date) + weight
        updatedAt = date
    }

    public func energy(at date: Date) -> Double {
        guard let updatedAt else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(updatedAt))
        return energy * pow(0.5, elapsed / Self.halfLife)
    }

    public func level(at date: Date) -> Double {
        1 - exp(-energy(at: date) / Self.scale)
    }
}

/// Decides which taps actually buzz a player's wrist.
public struct ChantPlayer: Hashable, Sendable {
    /// At most one chant this often.
    public static let minimumGap: TimeInterval = 4
    /// The same friend can't buzz more than this often.
    public static let perSenderGap: TimeInterval = 15

    private var lastPlayed: Date?
    private var lastBySender: [PlayerID: Date] = [:]

    public init() {}

    public mutating func shouldPlay(_ tap: CrowdTap, now: Date) -> Bool {
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < Self.minimumGap { return false }
        if let last = lastBySender[tap.from], now.timeIntervalSince(last) < Self.perSenderGap { return false }
        lastPlayed = now
        lastBySender[tap.from] = now
        return true
    }
}
