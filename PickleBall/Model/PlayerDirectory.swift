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

    private enum Keys {
        /// The phone's own (signed-out) player.
        static let anonymousID = "directory.anonymousPlayerID"
        /// Accounts that have answered "add this phone's matches?".
        static let adoptionAnswered = "directory.adoptionAnswered"
        static let legacyStamped = "directory.legacyOwnerStamped"
    }

    /// The signed-out player for this phone, created once.
    private var anonymousID: UUID {
        if let raw = UserDefaults.standard.string(forKey: Keys.anonymousID), let id = UUID(uuidString: raw) { return id }
        // First run after the update: the local player so far is anonymous
        // unless it already carries an account id (adopted by an older build).
        let local = ensureLocalUser()
        let id = local.kind == .user && Social.shared.userID == local.id ? UUID() : local.id
        UserDefaults.standard.set(id.uuidString, forKey: Keys.anonymousID)
        return id
    }

    /// Makes `id` the device owner. Every other record stops being local.
    private func activate(_ id: UUID, kind: PlayerKind, displayName: String) {
        let descriptor = FetchDescriptor<PlayerRecord>(predicate: #Predicate { $0.isLocalUser })
        for record in (try? context.fetch(descriptor)) ?? [] where record.id != id {
            record.isLocalUser = false
        }
        if let existing = fetch(id) {
            existing.isLocalUser = true
            existing.kindRaw = kind.rawValue
            existing.displayName = displayName
        } else {
            context.insert(PlayerRecord(id: id, kind: kind, displayName: displayName, isLocalUser: true))
        }
        AppDatabase.save()
    }

    /// Signing in. The account becomes the device owner; matches scored
    /// signed out are never relabelled automatically (on a shared phone
    /// they may be someone else's). Returns how many of them could be
    /// added to this account, so the app can ask.
    @discardableResult
    func adoptAccount(userID: UUID, displayName: String) -> Int {
        let anonymous = anonymousID
        AccountScope.current = userID
        activate(userID, kind: .user, displayName: displayName)
        stampLegacyRecords(for: userID)
        reload()
        MatchStore.shared.reload()
        WorkoutStore.shared.reload()
        let answered = Set(UserDefaults.standard.stringArray(forKey: Keys.adoptionAnswered) ?? [])
        guard !answered.contains(userID.uuidString) else { return 0 }
        return anonymousMatches(of: anonymous).count
    }

    /// Signing out: back to the phone's own player and history.
    func signOut() {
        AccountScope.current = nil
        activate(anonymousID, kind: .user, displayName: Self.profileDisplayName())
        reload()
        MatchStore.shared.reload()
        WorkoutStore.shared.reload()
    }

    /// The person said the signed-out matches are theirs: move them (and
    /// their workouts) to the account. Done once, by choice.
    func addAnonymousMatches(to userID: UUID, displayName: String) {
        let anonymous = anonymousID
        let account = PlayerRef(id: PlayerID(rawValue: userID), kind: .user, displayName: displayName)
        for match in anonymousMatches(of: anonymous) {
            guard var lineup = match.lineup else { continue }
            lineup.teams = lineup.teams.map { roster in roster.map { $0.id.rawValue == anonymous ? account : $0 } }
            match.lineupData = (try? JSONEncoder().encode(lineup)) ?? match.lineupData
            match.playerIDs = lineup.allPlayers.map(\.id.rawValue)
            match.ownerAccountID = userID
            let matchID: UUID? = match.id
            let workouts = FetchDescriptor<WorkoutSessionRecord>(predicate: #Predicate { $0.matchID == matchID })
            for workout in (try? context.fetch(workouts)) ?? [] where workout.ownerAccountID == nil {
                workout.ownerAccountID = userID
            }
        }
        answeredAdoption(for: userID)
        AppDatabase.save()
        MatchStore.shared.reload()
        WorkoutStore.shared.reload()
    }

    func answeredAdoption(for userID: UUID) {
        var answered = UserDefaults.standard.stringArray(forKey: Keys.adoptionAnswered) ?? []
        if !answered.contains(userID.uuidString) { answered.append(userID.uuidString) }
        UserDefaults.standard.set(answered, forKey: Keys.adoptionAnswered)
    }

    private func anonymousMatches(of anonymous: UUID) -> [MatchRecord] {
        let all = (try? context.fetch(FetchDescriptor<MatchRecord>())) ?? []
        return all.filter { $0.ownerAccountID == nil && $0.playerIDs.contains(anonymous) && $0.statusRaw != MatchStatus.live.rawValue }
    }

    /// Builds before account scoping relabelled matches to the account on
    /// sign-in and left them unowned. Those (and synced copies) belong to
    /// that account. Runs once.
    private func stampLegacyRecords(for userID: UUID) {
        guard !UserDefaults.standard.bool(forKey: Keys.legacyStamped) else { return }
        let all = (try? context.fetch(FetchDescriptor<MatchRecord>())) ?? []
        for match in all where match.ownerAccountID == nil && (match.playerIDs.contains(userID) || match.createdByID != nil) {
            match.ownerAccountID = userID
        }
        UserDefaults.standard.set(true, forKey: Keys.legacyStamped)
        AppDatabase.save()
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
