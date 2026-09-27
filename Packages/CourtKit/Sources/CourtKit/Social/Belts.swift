//
//  Belts.swift
//  CourtKit
//
//  The Belt is always on. It is never stored: it is a fold over confirmed
//  matches, so every phone derives the same holder from the same history
//  and nobody can edit a belt except by winning.
//
//  • Singles: the first confirmed match between two players creates their
//    belt. Every later match between them is a title match.
//  • Doubles: the same for two pairs. The pair holds the belt together.
//  • Squad: each squad has a singles and a doubles belt per sport. The
//    first squad match creates it; any squad match the holder plays is a
//    title match. Tournament matches are squad matches, so they count.
//
//  Only matches between accounts count. A guest can't hold a belt until
//  they claim their stats, at which point their matches count as theirs.
//

import Foundation

public enum BeltKind: String, Codable, Hashable, Sendable, CaseIterable {
    case singles
    case doubles
    case squadSingles
    case squadDoubles

    public var isSquad: Bool { self == .squadSingles || self == .squadDoubles }
    public var isDoubles: Bool { self == .doubles || self == .squadDoubles }
}

/// Which belt: the kind, the sport, and who it's between (or which squad).
public struct BeltKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let kind: BeltKind
    public let sport: Sport
    /// Singles and doubles: both sides, each sorted, sides sorted. Squad: empty.
    public let sides: [[PlayerID]]
    public let squadID: UUID?

    public static func rivalry(_ sideA: [PlayerID], _ sideB: [PlayerID], sport: Sport) -> BeltKey {
        let sides = [canonical(sideA), canonical(sideB)].sorted { tag($0) < tag($1) }
        return BeltKey(kind: sideA.count > 1 ? .doubles : .singles, sport: sport, sides: sides, squadID: nil)
    }

    public static func squad(_ squadID: UUID, doubles: Bool, sport: Sport) -> BeltKey {
        BeltKey(kind: doubles ? .squadDoubles : .squadSingles, sport: sport, sides: [], squadID: squadID)
    }

    /// Stable string form, for dictionary keys on the wire and in chat events.
    public var description: String {
        let who = squadID?.uuidString ?? sides.map(Self.tag).joined(separator: "|")
        return "\(kind.rawValue):\(sport.rawValue):\(who)"
    }

    public func involves(_ player: PlayerID) -> Bool {
        sides.contains { $0.contains(player) }
    }

    static func canonical(_ side: [PlayerID]) -> [PlayerID] {
        side.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }

    static func tag(_ side: [PlayerID]) -> String {
        side.map(\.rawValue.uuidString).joined(separator: "+")
    }
}

/// How the belt looks. It upgrades as the current holder racks up defenses.
public enum BeltTier: Int, Codable, Hashable, Sendable, Comparable, CaseIterable {
    case plain = 0
    case gold = 1
    case undisputed = 2

    public static let goldDefenses = 3
    public static let undisputedDefenses = 5

    public init(defenses: Int) {
        switch defenses {
        case Self.undisputedDefenses...: self = .undisputed
        case Self.goldDefenses...: self = .gold
        default: self = .plain
        }
    }

    public static func < (lhs: BeltTier, rhs: BeltTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .plain: return "Belt"
        case .gold: return "Gold Belt"
        case .undisputed: return "Undisputed Belt"
        }
    }

    /// Defenses still needed for the next tier.
    public static func defensesToNextTier(from defenses: Int) -> Int? {
        switch BeltTier(defenses: defenses) {
        case .plain: return goldDefenses - defenses
        case .gold: return undisputedDefenses - defenses
        case .undisputed: return nil
        }
    }
}

/// One holder's time with a belt.
public struct Reign: Hashable, Codable, Sendable {
    public let holder: [PlayerID]
    public let wonIn: UUID
    public let start: Date
    public internal(set) var defenses: Int
    public internal(set) var end: Date?
    public internal(set) var lostIn: UUID?

    public var isCurrent: Bool { end == nil }

    public func duration(asOf now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    public func days(asOf now: Date) -> Int {
        max(0, Int(duration(asOf: now) / 86_400))
    }

    public var tier: BeltTier { BeltTier(defenses: defenses) }
}

/// A title match and what it did to the belt.
public struct TitleBout: Hashable, Codable, Sendable {
    public enum Outcome: String, Codable, Hashable, Sendable {
        case created
        case defended
        case changedHands
    }

    public let matchID: UUID
    public let date: Date
    public let winners: [PlayerID]
    public let losers: [PlayerID]
    public let outcome: Outcome
}

public struct Belt: Hashable, Codable, Sendable, Identifiable {
    public let key: BeltKey
    /// Oldest first. The last one is current.
    public internal(set) var reigns: [Reign]
    /// Oldest first.
    public internal(set) var bouts: [TitleBout]

    public var id: String { key.description }

    public var currentReign: Reign? { reigns.last }
    public var holder: [PlayerID]? { currentReign?.holder }
    public var defenses: Int { currentReign?.defenses ?? 0 }
    public var tier: BeltTier { BeltTier(defenses: defenses) }

    public func isHeld(by player: PlayerID) -> Bool { holder?.contains(player) == true }

    /// Longest reign by time held; ties go to more defenses, then the latest.
    public func longestReign(asOf now: Date) -> Reign? {
        reigns.enumerated().max { lhs, rhs in
            let l = lhs.element.duration(asOf: now), r = rhs.element.duration(asOf: now)
            if l != r { return l < r }
            if lhs.element.defenses != rhs.element.defenses { return lhs.element.defenses < rhs.element.defenses }
            return lhs.offset < rhs.offset
        }?.element
    }

    /// Most defenses in a single reign.
    public var mostDefenses: Int { reigns.map(\.defenses).max() ?? 0 }

    public func totalReigns(of player: PlayerID) -> Int {
        reigns.filter { $0.holder.contains(player) }.count
    }

    /// Title-match record for a player (or pair member).
    public func record(of player: PlayerID) -> (wins: Int, losses: Int) {
        bouts.reduce(into: (0, 0)) { tally, bout in
            if bout.winners.contains(player) { tally.0 += 1 } else if bout.losers.contains(player) { tally.1 += 1 }
        }
    }
}

/// What a confirmed match did to the belts. Posted to chat as events and
/// used to decide when to offer a share card.
public enum BeltEvent: Hashable, Codable, Sendable {
    case created(key: BeltKey, holder: [PlayerID], matchID: UUID)
    case defended(key: BeltKey, holder: [PlayerID], defenses: Int, matchID: UUID)
    case changedHands(key: BeltKey, from: [PlayerID], to: [PlayerID], matchID: UUID)

    public var key: BeltKey {
        switch self {
        case .created(let key, _, _), .defended(let key, _, _, _), .changedHands(let key, _, _, _): return key
        }
    }

    public var matchID: UUID {
        switch self {
        case .created(_, _, let id), .defended(_, _, _, let id), .changedHands(_, _, _, let id): return id
        }
    }

    /// Who holds the belt after the match.
    public var holder: [PlayerID] {
        switch self {
        case .created(_, let holder, _), .defended(_, let holder, _, _): return holder
        case .changedHands(_, _, let to, _): return to
        }
    }

    /// Worth a share prompt: a belt changing hands, or a defense that
    /// upgrades the belt's art.
    public var isShareWorthy: Bool {
        switch self {
        case .created: return false
        case .changedHands: return true
        case .defended(_, _, let defenses, _):
            return defenses == BeltTier.goldDefenses || defenses == BeltTier.undisputedDefenses
        }
    }
}

public struct BeltLedger: Hashable, Sendable {
    public private(set) var belts: [BeltKey: Belt] = [:]
    public private(set) var eventsByMatch: [UUID: [BeltEvent]] = [:]
    private var seen: Set<UUID> = []

    public init() {}

    /// Folds confirmed matches oldest first. Unconfirmed or disputed matches
    /// must not be passed in.
    public static func compute(_ results: [MatchResult]) -> BeltLedger {
        var ledger = BeltLedger()
        for result in results.sorted(by: Self.chronological) {
            ledger.record(result)
        }
        return ledger
    }

    static func chronological(_ lhs: MatchResult, _ rhs: MatchResult) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Adds one confirmed match. Must be called in chronological order;
    /// a match already recorded is ignored.
    @discardableResult
    public mutating func record(_ result: MatchResult) -> [BeltEvent] {
        guard !seen.contains(result.id) else { return eventsByMatch[result.id] ?? [] }
        seen.insert(result.id)
        guard let winner = result.winner, Self.isEligible(result) else { return [] }

        let winners = result.lineup.teams[winner].map(\.id)
        let losers = result.lineup.teams[winner.opponent].map(\.id)
        var keys = [BeltKey.rivalry(winners, losers, sport: result.sport)]
        if let squad = result.squadID {
            keys.append(.squad(squad, doubles: winners.count > 1, sport: result.sport))
        }

        var events: [BeltEvent] = []
        for key in keys {
            if let event = apply(key: key, winners: winners, losers: losers, result: result) {
                events.append(event)
            }
        }
        if !events.isEmpty { eventsByMatch[result.id] = events }
        return events
    }

    /// Accounts only, same number on each side, singles or doubles.
    static func isEligible(_ result: MatchResult) -> Bool {
        let a = result.lineup.teams.a, b = result.lineup.teams.b
        guard a.count == b.count, (1...2).contains(a.count) else { return false }
        let everyone = a + b
        guard everyone.allSatisfy({ $0.kind == .user }) else { return false }
        return Set(everyone.map(\.id)).count == everyone.count
    }

    private mutating func apply(key: BeltKey, winners: [PlayerID], losers: [PlayerID], result: MatchResult) -> BeltEvent? {
        let winnerSet = Set(winners), loserSet = Set(losers)
        guard var belt = belts[key] else {
            belts[key] = Belt(
                key: key,
                reigns: [Reign(holder: BeltKey.canonical(winners), wonIn: result.id, start: result.date, defenses: 0)],
                bouts: [TitleBout(matchID: result.id, date: result.date, winners: winners, losers: losers, outcome: .created)]
            )
            return .created(key: key, holder: BeltKey.canonical(winners), matchID: result.id)
        }
        guard let holder = belt.holder else { return nil }
        let holderSet = Set(holder)

        let event: BeltEvent
        if holderSet == winnerSet {
            belt.reigns[belt.reigns.count - 1].defenses += 1
            belt.bouts.append(TitleBout(matchID: result.id, date: result.date, winners: winners, losers: losers, outcome: .defended))
            event = .defended(key: key, holder: holder, defenses: belt.defenses, matchID: result.id)
        } else if holderSet == loserSet {
            belt.reigns[belt.reigns.count - 1].end = result.date
            belt.reigns[belt.reigns.count - 1].lostIn = result.id
            let newHolder = BeltKey.canonical(winners)
            belt.reigns.append(Reign(holder: newHolder, wonIn: result.id, start: result.date, defenses: 0))
            belt.bouts.append(TitleBout(matchID: result.id, date: result.date, winners: winners, losers: losers, outcome: .changedHands))
            event = .changedHands(key: key, from: holder, to: newHolder, matchID: result.id)
        } else {
            // A squad match without the holder (or a split holding pair)
            // isn't a title match.
            return nil
        }
        belts[key] = belt
        return event
    }

    // MARK: - Queries

    public func belt(_ key: BeltKey) -> Belt? { belts[key] }

    public func events(for matchID: UUID) -> [BeltEvent] { eventsByMatch[matchID] ?? [] }

    public func isTitleMatch(_ matchID: UUID) -> Bool { eventsByMatch[matchID]?.isEmpty == false }

    /// Belts a player holds right now, best-looking first.
    public func held(by player: PlayerID) -> [Belt] {
        belts.values
            .filter { $0.isHeld(by: player) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier > $1.tier }
                if $0.defenses != $1.defenses { return $0.defenses > $1.defenses }
                return $0.id < $1.id
            }
    }

    /// Every belt a player has a stake in (between them and someone, or in
    /// one of their squads where they've fought for it).
    public func belts(involving player: PlayerID) -> [Belt] {
        belts.values
            .filter { $0.key.involves(player) || $0.bouts.contains { $0.winners.contains(player) || $0.losers.contains(player) } }
            .sorted { $0.id < $1.id }
    }

    /// The singles belts between two friends (one per sport played), for the
    /// direct-chat banner and the rivalry section.
    public func rivalryBelts(between a: PlayerID, and b: PlayerID) -> [Belt] {
        Sport.allCases.compactMap { belts[.rivalry([a], [b], sport: $0)] }
    }

    public func squadBelts(_ squadID: UUID) -> [Belt] {
        belts.values.filter { $0.key.squadID == squadID }.sorted { $0.id < $1.id }
    }
}
