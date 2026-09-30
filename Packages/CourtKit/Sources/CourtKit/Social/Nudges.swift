//
//  Nudges.swift
//  CourtKit
//
//  Bringing people back, low-key. Two things live here:
//
//  • Teaser notifications — one short line ("👀 Sam's still wearing your
//    belt"), the details only in the app, at most one a day, never at
//    night, never the same tease twice in a few days, each kind mutable.
//  • The belt widget — a friend's face, the belt, a day count. No
//    headline. The widget reads a small snapshot the app writes.
//
//  The words are the app's (so they can be translated); this decides what
//  to say and when.
//

import Foundation

// MARK: - Teaser notifications

public struct Nudge: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// A friend is holding a belt they took from you. "👀 Sam's still wearing your belt"
        case beltTaken
        /// A result is waiting on your confirmation. "🤝 Sam's waiting on you"
        case confirmWaiting
        /// Someone called you out. "⚔️ Sam called you out"
        case calledOut
        /// Your reign hit a milestone. "👑 30d"
        case reignMilestone
    }

    public let kind: Kind
    /// First names of whoever it's about ("Sam", "Sam & Alex").
    public let name: String
    public let days: Int?
    /// Identity for "don't tease the same thing twice".
    public let key: String

    public init(kind: Kind, name: String, days: Int? = nil, key: String) {
        self.kind = kind
        self.name = name
        self.days = days
        self.key = key
    }

    /// Lower goes first.
    var priority: Int {
        switch self.kind {
        case .confirmWaiting: return 0
        case .calledOut: return 1
        case .beltTaken: return 2
        case .reignMilestone: return 3
        }
    }
}

/// What's been sent, kept on the device.
public struct NudgeHistory: Hashable, Codable, Sendable {
    public var lastSent: Date?
    public var sentKeys: [String: Date] = [:]

    public init() {}

    public mutating func sent(_ nudge: Nudge, at date: Date) {
        lastSent = date
        sentKeys[nudge.key] = date
        // Forget anything older than a month.
        sentKeys = sentKeys.filter { date.timeIntervalSince($0.value) < 30 * 86_400 }
    }
}

public struct NudgePolicy: Hashable, Sendable {
    public var muted: Set<Nudge.Kind> = []
    /// Local hours when nothing is sent: from `quietStart` until `quietEnd`.
    public var quietStart = 21
    public var quietEnd = 9
    /// The same tease isn't repeated for this long.
    public var repeatAfter: TimeInterval = 3 * 86_400

    public init(muted: Set<Nudge.Kind> = []) { self.muted = muted }
}

public enum Nudges {
    public static let reignMilestones = [7, 14, 30, 50, 100, 200, 365]

    /// Everything worth a nudge right now.
    ///
    /// - Parameters:
    ///   - name: first name for a player (nil for people you can't see).
    ///   - waitingOn: who recorded each result you haven't confirmed.
    ///   - calledOutBy: who sent each open call out to you.
    public static func candidates(
        me: PlayerID,
        ledger: BeltLedger,
        name: (PlayerID) -> String?,
        waitingOn: [(matchID: UUID, from: PlayerID)] = [],
        calledOutBy: [(calloutID: UUID, from: PlayerID)] = [],
        now: Date = Date()
    ) -> [Nudge] {
        var out: [Nudge] = []
        for item in waitingOn {
            if let n = name(item.from) { out.append(Nudge(kind: .confirmWaiting, name: n, key: "confirm-\(item.matchID)")) }
        }
        for item in calledOutBy {
            if let n = name(item.from) { out.append(Nudge(kind: .calledOut, name: n, key: "callout-\(item.calloutID)")) }
        }
        for belt in ledger.belts(involving: me) {
            guard let reign = belt.currentReign else { continue }
            let days = reign.days(asOf: now)
            if reign.holder.contains(me) {
                if let milestone = reignMilestones.last(where: { $0 <= days }), days - milestone < 3 {
                    out.append(Nudge(kind: .reignMilestone, name: "", days: milestone,
                                     key: "reign-\(belt.id)-\(reign.wonIn)-\(milestone)"))
                }
            } else if belt.reigns.dropLast().last?.holder.contains(me) == true, days >= 2 {
                // They took it from me and still have it.
                let names = reign.holder.compactMap(name)
                guard names.count == reign.holder.count else { continue }
                out.append(Nudge(kind: .beltTaken, name: names.joined(separator: " & "), days: days,
                                 key: "taken-\(belt.id)-\(reign.wonIn)-\(days / 7)"))
            }
        }
        return out.sorted { ($0.priority, $0.key) < ($1.priority, $1.key) }
    }

    /// The one nudge to send and when, or nil for nothing today.
    public static func choose(
        from candidates: [Nudge],
        history: NudgeHistory,
        policy: NudgePolicy = NudgePolicy(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (nudge: Nudge, at: Date)? {
        let fresh = candidates.filter { nudge in
            guard !policy.muted.contains(nudge.kind) else { return false }
            if let sent = history.sentKeys[nudge.key], now.timeIntervalSince(sent) < policy.repeatAfter { return false }
            return true
        }
        guard let nudge = fresh.min(by: { ($0.priority, $0.key) < ($1.priority, $1.key) }) else { return nil }

        var at = now
        let hour = calendar.component(.hour, from: now)
        if hour >= policy.quietStart || hour < policy.quietEnd {
            // Next morning (or this morning, after midnight).
            let day = hour >= policy.quietStart ? calendar.date(byAdding: .day, value: 1, to: now)! : now
            at = calendar.date(bySettingHour: policy.quietEnd, minute: 30, second: 0, of: day)!
        }
        if let last = history.lastSent, calendar.isDate(last, inSameDayAs: at) {
            // One a day: tomorrow morning.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: at)!
            at = calendar.date(bySettingHour: policy.quietEnd, minute: 30, second: 0, of: tomorrow)!
        }
        return (nudge, at)
    }
}

// MARK: - Belt widget

/// What the belt widget shows, written by the app into the shared
/// container. Days are counted from `since` so the widget stays right
/// without the app running.
public struct BeltWidgetSnapshot: Hashable, Codable, Sendable {
    public struct Entry: Hashable, Codable, Sendable, Identifiable {
        public let beltID: String
        public let sport: Sport
        public let tier: BeltTier
        /// Whoever is wearing it (first names).
        public let holderName: String
        public let initials: String
        /// Avatar image file in the shared container.
        public let avatarFile: String?
        public let since: Date
        public let isMine: Bool

        public var id: String { beltID }

        public init(beltID: String, sport: Sport, tier: BeltTier, holderName: String, initials: String,
                    avatarFile: String?, since: Date, isMine: Bool) {
            self.beltID = beltID
            self.sport = sport
            self.tier = tier
            self.holderName = holderName
            self.initials = initials
            self.avatarFile = avatarFile
            self.since = since
            self.isMine = isMine
        }

        public func days(asOf now: Date) -> Int { max(0, Int(now.timeIntervalSince(since) / 86_400)) }

        /// "12d"
        public func dayCount(asOf now: Date) -> String { "\(days(asOf: now))d" }
    }

    public let entries: [Entry]
    public let generatedAt: Date

    public init(entries: [Entry], generatedAt: Date) {
        self.entries = entries
        self.generatedAt = generatedAt
    }

    public static let empty = BeltWidgetSnapshot(entries: [], generatedAt: .distantPast)

    /// Belts in play around me: friends wearing belts I've held come first
    /// (the itch), then belts I hold, longest-held first.
    public static func make(
        me: PlayerID,
        ledger: BeltLedger,
        names: (PlayerID) -> String?,
        avatarFile: (PlayerID) -> String? = { _ in nil },
        now: Date = Date(),
        limit: Int = 4
    ) -> BeltWidgetSnapshot {
        var theirs: [Entry] = []
        var mine: [Entry] = []
        for belt in ledger.belts(involving: me) {
            guard let reign = belt.currentReign else { continue }
            let isMine = reign.holder.contains(me)
            let names = reign.holder.compactMap(names)
            guard names.count == reign.holder.count else { continue }
            let everHeld = belt.reigns.contains { $0.holder.contains(me) }
            guard isMine || everHeld else { continue }
            let entry = Entry(
                beltID: belt.id, sport: belt.key.sport, tier: reign.tier,
                holderName: names.joined(separator: " & "),
                initials: names.compactMap(\.first).map(String.init).joined().uppercased(),
                avatarFile: reign.holder.count == 1 ? avatarFile(reign.holder[0]) : nil,
                since: reign.start, isMine: isMine
            )
            if isMine { mine.append(entry) } else { theirs.append(entry) }
        }
        let order: (Entry, Entry) -> Bool = { ($0.since, $0.beltID) < ($1.since, $1.beltID) }
        return BeltWidgetSnapshot(entries: Array((theirs.sorted(by: order) + mine.sorted(by: order)).prefix(limit)),
                                  generatedAt: now)
    }
}
