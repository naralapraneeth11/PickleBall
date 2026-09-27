//
//  PlayerDirectory.swift
//  PickleBall
//
//  Every player is a user ID or a guest ID, never a plain name string. The
//  directory owns the local user (the device owner) and the guests added
//  at the court, and turns picker selections into `PlayerRef`s.
//

import Foundation
import Combine
import SwiftData
import CourtKit

@MainActor
final class PlayerDirectory: ObservableObject {
    static let shared = PlayerDirectory()

    /// The device owner.
    @Published private(set) var me: PlayerRef
    /// Friends and people you've played, most recently played first.
    @Published private(set) var others: [PlayerRef] = []
    /// Accounts you're friends with.
    @Published private(set) var friendIDs: Set<PlayerID> = []

    private var context: ModelContext { AppDatabase.context }

    private init() {
        me = PlayerRef(kind: .user, displayName: "You")
        me = ensureLocalUser().ref
        reload()
    }

    // MARK: Local user

    /// Returns the device owner's record, creating it on first launch.
    @discardableResult
    func ensureLocalUser() -> PlayerRecord {
        var descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.isLocalUser })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let record = PlayerRecord(kind: .user, displayName: Self.profileDisplayName(), isLocalUser: true)
        context.insert(record)
        AppDatabase.save()
        return record
    }

    /// Keeps the local user's display name in step with the profile.
    func syncProfileName() {
        let record = ensureLocalUser()
        let name = Self.profileDisplayName()
        guard record.displayName != name else { return }
        record.displayName = name
        AppDatabase.save()
        me = record.ref
    }

    static func profileDisplayName() -> String {
        let first = (UserDefaults.standard.string(forKey: "profile_firstName") ?? "").trimmingCharacters(in: .whitespaces)
        let last = (UserDefaults.standard.string(forKey: "profile_lastName") ?? "").trimmingCharacters(in: .whitespaces)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "You" : full
    }

    // MARK: Lookup

    func reload() {
        let descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { !$0.isLocalUser })
        let records = (try? context.fetch(descriptor)) ?? []
        // Players seen only in friends' matches stay out of the pickers.
        let friends = friendIDs
        others = records
            .filter { $0.lastPlayedAt != nil || friends.contains(PlayerID(rawValue: $0.id)) }
            .sorted { ($0.lastPlayedAt ?? .distantPast, $0.displayName) > ($1.lastPlayedAt ?? .distantPast, $1.displayName) }
            .map(\.ref)
        me = ensureLocalUser().ref
    }

    // MARK: Account

    /// Makes the device owner's player ID the account ID, rewriting any
    /// matches recorded before sign-in, and takes the profile name.
    func adoptAccount(userID: UUID, displayName: String) {
        let record = ensureLocalUser()
        let oldID = record.id
        if oldID != userID {
            let account = PlayerRef(id: PlayerID(rawValue: userID), kind: .user, displayName: displayName)
            for match in (try? context.fetch(FetchDescriptor<MatchRecord>())) ?? [] where match.playerIDs.contains(oldID) {
                guard var lineup = match.lineup else { continue }
                lineup.teams = lineup.teams.map { roster in roster.map { $0.id.rawValue == oldID ? account : $0 } }
                match.lineupData = (try? JSONEncoder().encode(lineup)) ?? match.lineupData
                match.playerIDs = lineup.allPlayers.map(\.id.rawValue)
            }
            if let existing = fetch(userID) {
                existing.isLocalUser = true
                existing.kindRaw = PlayerKind.user.rawValue
                context.delete(record)
            } else {
                record.id = userID
            }
        }
        let current = ensureLocalUser()
        current.displayName = displayName
        current.kindRaw = PlayerKind.user.rawValue
        AppDatabase.save()
        reload()
        if oldID != userID { MatchStore.shared.reload() }
    }

    /// Friends are players you can pick for a match.
    func upsertFriends(_ friends: [PlayerRef]) {
        var changed = false
        for friend in friends {
            if let record = fetch(friend.id.rawValue) {
                if record.displayName != friend.displayName || record.kind != .user {
                    record.displayName = friend.displayName
                    record.kindRaw = PlayerKind.user.rawValue
                    changed = true
                }
            } else {
                context.insert(PlayerRecord(id: friend.id.rawValue, kind: .user, displayName: friend.displayName))
                changed = true
            }
        }
        let ids = Set(friends.map(\.id))
        if changed { AppDatabase.save() }
        if changed || ids != friendIDs {
            friendIDs = ids
            reload()
        }
    }

    private func fetch(_ id: UUID) -> PlayerRecord? {
        var descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Guests created on this phone, for claim links.
    var guests: [PlayerRef] {
        others.filter { $0.kind == .guest }
    }

    func player(_ id: PlayerID) -> PlayerRef? {
        if id == me.id { return me }
        if let known = others.first(where: { $0.id == id }) { return known }
        return fetch(id.rawValue)?.ref
    }

    /// Known players whose name contains `query`, best matches first.
    func suggestions(for query: String, excluding excluded: Set<PlayerID> = [], limit: Int = 6) -> [PlayerRef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = ([me] + others).filter { !excluded.contains($0.id) }
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }
        let prefix = pool.filter { $0.displayName.lowercased().hasPrefix(q) }
        let contains = pool.filter { !$0.displayName.lowercased().hasPrefix(q) && $0.displayName.lowercased().contains(q) }
        return Array((prefix + contains).prefix(limit))
    }

    // MARK: Guests

    /// Adds a new guest. Two guests may share a name; they stay distinct.
    @discardableResult
    func addGuest(named name: String) -> PlayerRef {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = PlayerRecord(kind: .guest, displayName: trimmed.isEmpty ? "Guest" : trimmed)
        context.insert(record)
        AppDatabase.save()
        reload()
        return record.ref
    }

    /// Resolves a typed name when the user didn't pick a suggestion: reuses
    /// the most recently played player with exactly that name, otherwise
    /// creates a guest. Selecting from suggestions is always exact.
    func resolve(typedName name: String) -> PlayerRef {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return addGuest(named: "Guest") }
        if trimmed.caseInsensitiveCompare(me.displayName) == .orderedSame
            || trimmed.caseInsensitiveCompare(me.shortName) == .orderedSame {
            return me
        }
        if let known = others.first(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return known
        }
        return addGuest(named: trimmed)
    }

    /// Makes sure every player in a lineup exists (e.g. guests created on the Watch).
    func adopt(_ lineup: Lineup) {
        var changed = false
        for player in lineup.allPlayers where player.id != me.id {
            let raw = player.id.rawValue
            var descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == raw })
            descriptor.fetchLimit = 1
            if (try? context.fetch(descriptor).first) == nil {
                context.insert(PlayerRecord(id: raw, kind: player.kind, displayName: player.displayName))
                changed = true
            }
        }
        if changed {
            AppDatabase.save()
            reload()
        }
    }

    func markPlayed(_ lineup: Lineup, at date: Date = Date()) {
        let ids = Set(lineup.allPlayers.map(\.id.rawValue))
        let descriptor = FetchDescriptor<PlayerRecord>()
        for record in (try? context.fetch(descriptor)) ?? [] where ids.contains(record.id) {
            record.lastPlayedAt = date
        }
        AppDatabase.save()
        reload()
    }

    func rename(_ id: PlayerID, to name: String) {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.id == raw })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        record.displayName = name
        AppDatabase.save()
        reload()
    }
}
