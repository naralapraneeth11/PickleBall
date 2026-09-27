//
//  Social.swift
//  PickleBall
//
//  The signed-in side of the app: account, friends, squads, chats, call
//  outs, squad tournaments, trophies, Replays, the Feed and live matches.
//
//  Offline first: everything shown comes from memory, restored from a
//  cache at launch, so every screen opens instantly with no signal. Reads
//  refresh from Supabase when they can; writes that must survive a dead
//  zone go through the outbox. Realtime nudges the right collection to
//  refresh when a friend does something.
//

import Foundation
import Network
import Observation
import SwiftUI
import CourtKit
import CourtNet

@MainActor
@Observable
final class Social {
    static let shared = Social()

    enum Phase: Equatable {
        /// Restoring the session.
        case launching
        case signedOut
        /// Signed in, but no username yet.
        case needsProfile
        case ready
        /// Built without a server (no Secrets.plist): scoring only.
        case offlineOnly
    }

    // MARK: State

    private(set) var phase: Phase = .launching
    private(set) var userID: UUID?
    private(set) var profile: ProfileRow?

    /// Everyone we can show a name and photo for: friends, squadmates,
    /// people with a pending request.
    private(set) var profiles: [UUID: ProfileRow] = [:]
    private(set) var friendships: [FriendshipRow] = []
    private(set) var blocked: Set<UUID> = []
    private(set) var squads: [SquadRow] = []
    private(set) var squadMembers: [SquadMemberRow] = []
    private(set) var conversations: [ConversationRow] = []
    private(set) var messages: [UUID: [MessageRow]] = [:]
    private(set) var callOuts: [CallOutRow] = []
    private(set) var tournaments: [TournamentRow] = []
    private(set) var entrants: [EntrantRow] = []
    private(set) var fixtures: [FixtureRow] = []
    private(set) var trophies: [TrophyRow] = []
    private(set) var replays: [ReplayRow] = []
    private(set) var feed: [ServeRow] = []
    private(set) var myServes: [ServeRow] = []
    private(set) var returns: [UUID: [ReturnRow]] = [:]
    private(set) var liveMatches: [LiveMatchRow] = []
    /// Participants of matches still waiting on someone, for "confirm" lists.
    private(set) var pendingParticipants: [UUID: [ParticipantRow]] = [:]
    /// Player rows (guests and users) seen in shared matches and tournaments.
    private(set) var players: [UUID: PlayerRow] = [:]

    private(set) var isOnline = true
    private(set) var isRefreshing = false
    private(set) var outboxCount = 0
    private(set) var refusedWrites: [OutboxOperation] = []
    /// Last thing that went wrong, for a toast.
    var notice: String?

    /// When each chat was last opened, for unread dots.
    private(set) var lastRead: [UUID: Date] = [:]

    /// A share card waiting to be offered (belt won, trophy, comeback).
    var sharePrompt: SharePrompt?
    /// An invite opened before the account was ready.
    var pendingInvite: InviteLink?

    // Live matches and crowd taps (Social+Live.swift).
    @ObservationIgnored var hostCrowd: CrowdChannel?
    @ObservationIgnored var hostCrowdTask: Task<Void, Never>?
    @ObservationIgnored var liveUpdateTask: Task<Void, Never>?
    @ObservationIgnored var lastLivePublish: Date = .distantPast
    @ObservationIgnored var spectatorCrowd: CrowdChannel?

    // MARK: Plumbing

    let backend: SupabaseBackend?
    @ObservationIgnored private var outbox: Outbox?
    @ObservationIgnored private var live: LiveUpdates?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var cacheSave: Task<Void, Never>?
    @ObservationIgnored var matchCursor: Date?

    var invitePage: URL? { backend?.config.invitePage }

    private init() {
        backend = BackendConfig.fromBundle().map(SupabaseBackend.init(config:))
    }

    /// Call once at launch.
    func boot() {
        guard let backend else {
            phase = .offlineOnly
            return
        }
        // The monitor calls back on its own queue; hop to the main actor
        // through the singleton rather than capturing self across threads.
        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Social.shared.networkChanged(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Social.path"))

        authTask = Task { [weak self] in
            for await state in backend.authStates() {
                await self?.authChanged(state)
            }
        }
    }

    private func authChanged(_ state: AuthState) async {
        switch state {
        case .signedOut:
            guard phase != .signedOut else { return }
            await tearDown()
            phase = .signedOut
        case .signedIn(let id):
            guard userID != id else { return }
            userID = id
            restoreCache(for: id)
            outbox = Outbox(storage: FileOutboxStorage(url: Self.directory(for: id).appendingPathComponent("outbox.json")))
            await updateOutboxState()
            if let profile {
                becomeReady(with: profile)
            }
            await loadProfile(id)
        }
    }

    private func loadProfile(_ id: UUID) async {
        guard let backend else { return }
        do {
            if let row = try await backend.profile(id: id) {
                becomeReady(with: row)
            } else {
                phase = .needsProfile
            }
        } catch {
            // Offline with no cached profile: let them in once we know more.
            if profile == nil { phase = .needsProfile }
        }
    }

    private func becomeReady(with row: ProfileRow) {
        profile = row
        profiles[row.id] = row
        let wasReady = phase == .ready
        phase = .ready
        PlayerDirectory.shared.adoptAccount(userID: row.id, displayName: row.displayName)
        guard !wasReady else { return }
        startRealtime()
        Task {
            await refreshAll()
            await drainOutbox()
            if let invite = pendingInvite {
                pendingInvite = nil
                await redeem(invite)
            }
        }
    }

    /// Opens an invite now, or once signed in.
    func open(_ link: InviteLink) {
        guard phase == .ready else {
            pendingInvite = link
            return
        }
        Task { await redeem(link) }
    }

    private func tearDown() async {
        liveTask?.cancel()
        await live?.stop()
        live = nil
        await outbox?.removeAll()
        outbox = nil
        userID = nil
        profile = nil
        profiles = [:]
        friendships = []
        blocked = []
        squads = []
        squadMembers = []
        conversations = []
        messages = [:]
        callOuts = []
        tournaments = []
        entrants = []
        fixtures = []
        trophies = []
        replays = []
        feed = []
        myServes = []
        returns = [:]
        liveMatches = []
        pendingParticipants = [:]
        players = [:]
        lastRead = [:]
        matchCursor = nil
        outboxCount = 0
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        guard cameBack, phase == .ready else { return }
        Task {
            await outbox?.resetBackoff()
            await drainOutbox()
            await refreshAll()
        }
    }

    // MARK: Account

    func signInWithApple(idToken: String, rawNonce: String) async {
        guard let backend else { return }
        do {
            try await backend.signInWithApple(idToken: idToken, rawNonce: rawNonce)
        } catch {
            notice = "Sign in didn’t work. \(error.localizedDescription)"
        }
    }

    func signOut() async {
        await backend?.signOut()
    }

    func deleteAccount() async -> Bool {
        guard let backend else { return false }
        do {
            try await backend.deleteAccount()
            if let userID { try? FileManager.default.removeItem(at: Self.directory(for: userID)) }
            return true
        } catch {
            notice = "Couldn’t delete your account. \(error.localizedDescription)"
            return false
        }
    }

    func saveProfile(username: String, displayName: String, sports: [Sport], homeCourts: [CourtTag], avatar: Data?) async -> Bool {
        guard let backend, let userID else { return false }
        do {
            var avatarPath = profile?.avatarPath
            if let avatar {
                let path = "\(userID.uuidString.lowercased())/avatar-\(Int(Date().timeIntervalSince1970)).jpg"
                avatarPath = try await backend.upload(avatar, to: .avatars, path: path, contentType: "image/jpeg")
            }
            let row = try await backend.saveProfile(ProfileDraft(
                id: userID, username: Username.normalize(username), displayName: displayName,
                avatarPath: avatarPath, sports: sports, homeCourts: homeCourts
            ))
            becomeReady(with: row)
            scheduleCacheSave()
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    func isUsernameAvailable(_ name: String) async -> Bool? {
        try? await backend?.isUsernameAvailable(name)
    }

    // MARK: Refreshing

    func refreshAll() async {
        guard phase == .ready, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let friends: Void = refreshFriends()
        async let squads: Void = refreshSquadsAndChats()
        async let callOuts: Void = refreshCallOuts()
        async let tournaments: Void = refreshTournaments()
        async let feed: Void = refreshFeed()
        async let replays: Void = refreshReplays()
        async let live: Void = refreshLiveMatches()
        _ = await (friends, squads, callOuts, tournaments, feed, replays, live)
        await refreshMatches()
        await refreshTrophies()
        scheduleCacheSave()
    }

    func refreshFriends() async {
        guard let backend else { return }
        do {
            async let rows = backend.friendships()
            async let blockedIDs = backend.blockedUsers()
            friendships = try await rows
            blocked = Set(try await blockedIDs)
            let me = userID
            await loadProfiles(friendships.compactMap { row in me.map { row.other(than: $0) } })
            syncFriendsIntoDirectory()
        } catch {
            report(error)
        }
    }

    func refreshSquadsAndChats() async {
        guard let backend else { return }
        do {
            async let squadRows = backend.squads()
            async let memberRows = backend.squadMembers()
            async let chatRows = backend.conversations()
            squads = try await squadRows
            squadMembers = try await memberRows
            conversations = try await chatRows
            let me = userID
            await loadProfiles(squadMembers.map(\.userID) + conversations.compactMap { row in me.flatMap { row.friend(of: $0) } })
        } catch {
            report(error)
        }
    }

    func refreshCallOuts() async {
        guard let backend else { return }
        do {
            callOuts = try await backend.callOuts()
            await loadPlayers(callOuts.flatMap { $0.challengers + $0.challenged })
        } catch {
            report(error)
        }
    }

    func refreshTournaments() async {
        guard let backend else { return }
        do {
            tournaments = try await backend.tournaments()
            let ids = tournaments.map(\.id)
            async let entrantRows = backend.entrants(tournamentIDs: ids)
            async let fixtureRows = backend.fixtures(tournamentIDs: ids)
            entrants = try await entrantRows
            fixtures = try await fixtureRows
            await loadPlayers(entrants.map(\.playerID))
        } catch {
            report(error)
        }
    }

    func refreshTrophies() async {
        guard let backend, let userID else { return }
        do {
            trophies = try await backend.trophies(ownerIDs: [userID] + friends.map(\.id))
        } catch {
            report(error)
        }
    }

    func refreshReplays() async {
        guard let backend else { return }
        do {
            replays = try await backend.replays()
        } catch {
            report(error)
        }
    }

    func refreshFeed() async {
        guard let backend, let userID else { return }
        do {
            async let feedRows = backend.feed()
            async let mine = backend.serves(by: userID)
            feed = try await feedRows.filter { !blocked.contains($0.authorID) }
            myServes = try await mine
            let serveIDs = (feed + myServes).filter { $0.rallyCount > 0 }.map(\.id)
            let rows = try await backend.returns(serveIDs: serveIDs)
            returns = Dictionary(grouping: rows.filter { !blocked.contains($0.authorID) }, by: \.serveID)
        } catch {
            report(error)
        }
    }

    func refreshLiveMatches() async {
        guard let backend else { return }
        do {
            liveMatches = try await backend.liveMatches().filter { $0.hostID != userID && $0.isFresh() }
        } catch {
            report(error)
        }
    }

    func loadMessages(in conversationID: UUID) async {
        guard let backend else { return }
        do {
            let known = messages[conversationID] ?? []
            let after = known.last(where: { !pendingMessageIDs.contains($0.id) })?.createdAt
            let rows = try await backend.messages(in: conversationID, after: after, limit: 200)
            merge(rows, into: conversationID)
        } catch {
            report(error)
        }
    }

    private func loadProfiles(_ ids: [UUID]) async {
        guard let backend else { return }
        let missing = Set(ids).subtracting([userID].compactMap { $0 })
        guard !missing.isEmpty else { return }
        if let rows = try? await backend.profiles(ids: Array(missing)) {
            for row in rows { profiles[row.id] = row }
        }
    }

    func loadPlayers(_ ids: [UUID]) async {
        guard let backend else { return }
        let missing = Set(ids).subtracting(players.keys)
        guard !missing.isEmpty else { return }
        if let rows = try? await backend.players(ids: Array(missing)) {
            for row in rows { players[row.id] = row }
        }
    }

    // MARK: Realtime

    private func startRealtime() {
        guard let backend, let userID, live == nil else { return }
        let updates = LiveUpdates(backend: backend)
        live = updates
        liveTask = Task { [weak self] in
            let stream = await updates.start(userID: userID)
            for await change in stream {
                self?.received(change)
            }
        }
    }

    private func received(_ change: LiveChange) {
        switch change {
        case .message(let message):
            guard !blocked.contains(message.senderID ?? UUID()) else { return }
            merge([message], into: message.conversationID)
            if let index = conversations.firstIndex(where: { $0.id == message.conversationID }) {
                conversations[index].lastMessageAt = message.createdAt
                conversations.sort { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
            }
            if case .result? = message.payload { debounce("matches") { await $0.refreshMatches() } }
        case .table(let table):
            switch table {
            case "friendships": debounce(table) { await $0.refreshFriends() }
            case "squad_members", "conversations": debounce("chats") { await $0.refreshSquadsAndChats() }
            case "matches", "match_participants": debounce("matches") { await $0.refreshMatches() }
            case "callouts": debounce(table) { await $0.refreshCallOuts() }
            case "tournaments", "tournament_fixtures": debounce("tournaments") { await $0.refreshTournaments() }
            case "serves", "returns": debounce("feed") { await $0.refreshFeed() }
            case "replays": debounce(table) { await $0.refreshReplays() }
            case "live_matches": debounce(table) { await $0.refreshLiveMatches() }
            default: break
            }
        }
    }

    /// Coalesces bursts of changes (a tournament result touches several
    /// tables) into one refresh.
    private func debounce(_ key: String, _ work: @escaping @MainActor (Social) async -> Void) {
        pendingRefresh[key]?.cancel()
        pendingRefresh[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            await work(self)
            self.scheduleCacheSave()
        }
    }

    // MARK: Outbox

    @ObservationIgnored private var pendingMessageIDs: Set<UUID> = []

    func enqueue(_ operation: OutboxOperation) async {
        guard let outbox else { return }
        await outbox.enqueue(operation)
        await updateOutboxState()
        await drainOutbox()
    }

    func drainOutbox() async {
        guard let outbox, let backend, phase == .ready else { return }
        let sent = await outbox.drain(using: backend)
        await updateOutboxState()
        if sent > 0 { debounce("matches") { await $0.refreshMatches() } }
    }

    private func updateOutboxState() async {
        guard let outbox else { return }
        outboxCount = await outbox.pending.count
        let refused = await outbox.rejected
        if refused.count > refusedWrites.count, let latest = refused.last?.lastError {
            notice = "Something couldn’t be sent: \(latest)"
        }
        refusedWrites = refused
    }

    // MARK: Chat writes

    func send(_ text: String, in conversationID: UUID, photo: Data? = nil) async {
        guard let userID else { return }
        var body: String?
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let cleaned = ContentFilter.standard.cleaned(text) else {
                notice = "That message breaks the community rules."
                return
            }
            body = cleaned
        }
        var mediaPath: String?
        if let photo {
            guard let path = await uploadMedia(photo, kind: "chat") else { return }
            mediaPath = path
        }
        guard body != nil || mediaPath != nil else { return }
        let draft = MessageDraft(conversationID: conversationID, senderID: userID, kind: mediaPath == nil ? .text : .photo,
                                 body: body, mediaPath: mediaPath)
        pendingMessageIDs.insert(draft.id)
        merge([draft.optimisticRow()], into: conversationID)
        do {
            await enqueue(try Operations.sendMessage(draft))
        } catch {
            report(error)
        }
    }

    private func merge(_ rows: [MessageRow], into conversationID: UUID) {
        var list = messages[conversationID] ?? []
        for row in rows {
            if let index = list.firstIndex(where: { $0.id == row.id }) {
                list[index] = row
                pendingMessageIDs.remove(row.id)
            } else if !blocked.contains(row.senderID ?? UUID()) {
                list.append(row)
            }
        }
        list.sort { $0.createdAt < $1.createdAt }
        messages[conversationID] = Array(list.suffix(500))
        scheduleCacheSave()
    }

    func isPending(_ message: MessageRow) -> Bool { pendingMessageIDs.contains(message.id) }

    func markRead(_ conversationID: UUID) {
        lastRead[conversationID] = Date()
        scheduleCacheSave()
    }

    func hasUnread(_ conversation: ConversationRow) -> Bool {
        guard let last = conversation.lastMessageAt else { return false }
        if let latest = messages[conversation.id]?.last, latest.senderID == userID { return false }
        return last > (lastRead[conversation.id] ?? .distantPast)
    }

    // MARK: Media

    /// Uploads a photo to the user's folder. Nil (with a notice) on failure.
    func uploadMedia(_ data: Data, kind: String, contentType: String = "image/jpeg") async -> String? {
        guard let backend, let userID else { return nil }
        let ext = contentType == "video/mp4" ? "mp4" : "jpg"
        let path = "\(userID.uuidString.lowercased())/\(kind)/\(UUID().uuidString.lowercased()).\(ext)"
        do {
            return try await backend.upload(data, to: .media, path: path, contentType: contentType)
        } catch {
            notice = "Upload failed. \(Self.message(for: error))"
            return nil
        }
    }

    func mediaURL(_ path: String, bucket: MediaBucket = .media) async -> URL? {
        try? await backend?.url(for: path, in: bucket)
    }

    // MARK: Running calls

    /// Runs a server call that needs a connection, turning failures into a
    /// notice. Returns false if it failed.
    @discardableResult
    func run(_ work: (SupabaseBackend) async throws -> Void) async -> Bool {
        guard let backend else {
            notice = BackendError.notConfigured.localizedDescription
            return false
        }
        do {
            try await work(backend)
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        if isOnline { print("Social:", error) }
    }

    static func message(for error: Error) -> String {
        if let error = error as? URLError, error.code == .notConnectedToInternet {
            return "You’re offline. Try again when you have signal."
        }
        let text = error.localizedDescription
        if text.contains("duplicate key") && text.contains("username") { return "That username is taken." }
        return text
    }

    // MARK: Cache

    private static func directory(for userID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Social/\(userID.uuidString.lowercased())", isDirectory: true)
    }

    private func restoreCache(for userID: UUID) {
        let url = Self.directory(for: userID).appendingPathComponent("cache.json")
        guard let data = try? Data(contentsOf: url),
              let cache = try? WireCoding.decoder.decode(SocialCache.self, from: data) else { return }
        profile = cache.profile
        profiles = Dictionary(cache.profiles.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        friendships = cache.friendships
        blocked = Set(cache.blocked)
        squads = cache.squads
        squadMembers = cache.squadMembers
        conversations = cache.conversations
        messages = cache.messages
        callOuts = cache.callOuts
        tournaments = cache.tournaments
        entrants = cache.entrants
        fixtures = cache.fixtures
        trophies = cache.trophies
        replays = cache.replays
        feed = cache.feed
        myServes = cache.myServes
        returns = cache.returns
        players = Dictionary(cache.players.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        pendingParticipants = cache.pendingParticipants
        lastRead = cache.lastRead
        matchCursor = cache.matchCursor
    }

    func scheduleCacheSave() {
        guard let userID else { return }
        cacheSave?.cancel()
        cacheSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let cache = SocialCache(
                profile: profile, profiles: Array(profiles.values), friendships: friendships, blocked: Array(blocked),
                squads: squads, squadMembers: squadMembers, conversations: conversations, messages: messages,
                callOuts: callOuts, tournaments: tournaments, entrants: entrants, fixtures: fixtures,
                trophies: trophies, replays: replays, feed: feed, myServes: myServes, returns: returns,
                players: Array(players.values), pendingParticipants: pendingParticipants, lastRead: lastRead,
                matchCursor: matchCursor
            )
            let directory = Self.directory(for: userID)
            Task.detached(priority: .utility) {
                guard let data = try? WireCoding.encoder.encode(cache) else { return }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: directory.appendingPathComponent("cache.json"), options: [.atomic, .completeFileProtection])
            }
        }
    }

    // MARK: Internal setters for extensions in other files

    func setPendingParticipants(_ value: [UUID: [ParticipantRow]]) { pendingParticipants = value }
    func mergePlayers(_ rows: [PlayerRow]) { for row in rows { players[row.id] = row } }
    func setCallOuts(_ rows: [CallOutRow]) { callOuts = rows }
    func setFriendships(_ rows: [FriendshipRow]) { friendships = rows }
    func setBlocked(_ ids: Set<UUID>) { blocked = ids }
    func setFeed(_ rows: [ServeRow]) { feed = rows }
    func setMyServes(_ rows: [ServeRow]) { myServes = rows }
    func setReturns(_ rows: [ReturnRow], for serveID: UUID) { returns[serveID] = rows }
    func setReplays(_ rows: [ReplayRow]) { replays = rows }
    func setSquads(_ rows: [SquadRow]) { squads = rows }
    func setFixtures(_ rows: [FixtureRow]) { fixtures = rows }
    func removeMessage(_ id: UUID, from conversationID: UUID) { messages[conversationID]?.removeAll { $0.id == id } }
}

/// Everything restored at launch for an instant, offline first screen.
nonisolated struct SocialCache: Codable, Sendable {
    var profile: ProfileRow?
    var profiles: [ProfileRow]
    var friendships: [FriendshipRow]
    var blocked: [UUID]
    var squads: [SquadRow]
    var squadMembers: [SquadMemberRow]
    var conversations: [ConversationRow]
    var messages: [UUID: [MessageRow]]
    var callOuts: [CallOutRow]
    var tournaments: [TournamentRow]
    var entrants: [EntrantRow]
    var fixtures: [FixtureRow]
    var trophies: [TrophyRow]
    var replays: [ReplayRow]
    var feed: [ServeRow]
    var myServes: [ServeRow]
    var returns: [UUID: [ReturnRow]]
    var players: [PlayerRow]
    var pendingParticipants: [UUID: [ParticipantRow]]
    var lastRead: [UUID: Date]
    var matchCursor: Date?
}
