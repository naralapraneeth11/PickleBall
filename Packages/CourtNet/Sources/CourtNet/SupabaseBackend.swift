//
//  SupabaseBackend.swift
//  CourtNet
//
//  SocialAPI over Supabase: PostgREST for rows and RPCs, Storage for
//  photos, GoTrue for Sign in with Apple. Every call runs as the signed-in
//  user, so row-level security decides what comes back.
//

import Foundation
@_exported import CourtNetCore
import CourtKit
import Supabase

/// Where the backend lives. Read from Secrets.plist (git-ignored, copied
/// from Secrets.example.plist), so keys never live in source control.
public struct BackendConfig: Sendable, Hashable {
    public let url: URL
    public let anonKey: String
    /// The invite landing page, if set.
    public let invitePage: URL?
    /// The public web site (web/ on Cloudflare Pages): live scoreboards,
    /// privacy policy, support.
    public let site: URL?

    public init(url: URL, anonKey: String, invitePage: URL? = nil, site: URL? = nil) {
        self.url = url
        self.anonKey = anonKey
        self.site = site
        self.invitePage = invitePage ?? site?.appendingPathComponent("invite/")
    }

    /// Nil when the app was built without Secrets.plist. Such a build can
    /// still score matches on the device, and says it isn't connected.
    public static func fromBundle(_ bundle: Bundle = .main) -> BackendConfig? {
        var values: [String: Any] = [:]
        if let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            values = plist
        }
        func value(_ key: String) -> String? {
            let raw = (values[key] as? String) ?? (bundle.object(forInfoDictionaryKey: key) as? String)
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  !raw.contains("$("), !raw.contains("YOUR-") else { return nil }
            return raw
        }
        func url(_ raw: String?) -> URL? {
            guard let raw else { return nil }
            return URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
        }
        guard let base = url(value("SUPABASE_URL")), let key = value("SUPABASE_ANON_KEY") else { return nil }
        return BackendConfig(url: base, anonKey: key, invitePage: url(value("INVITE_PAGE_URL")), site: url(value("SITE_URL")))
    }
}

public final class SupabaseBackend: SocialAPI, @unchecked Sendable {
    public let client: SupabaseClient
    public let config: BackendConfig
    private let urlCache = SignedURLCache()

    public init(config: BackendConfig) {
        self.config = config
        #if canImport(Security)
        let storage: any AuthLocalStorage = KeychainLocalStorage()
        #else
        let storage: any AuthLocalStorage = MemoryAuthStorage()
        #endif
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: WireCoding.encoder, decoder: WireCoding.decoder),
                auth: .init(storage: storage, flowType: .pkce, emitLocalSessionAsInitialSession: true)
            )
        )
    }

    var db: PostgrestClient { client.schema("public") }

    func me() throws -> UUID {
        guard let id = client.auth.currentUser?.id else { throw BackendError.signedOut }
        return id
    }

    // MARK: Profiles

    public func profile(id: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await db.from("profiles").select().eq("id", value: id).limit(1).execute().value
        return rows.first
    }

    public func profiles(ids: [UUID]) async throws -> [ProfileRow] {
        try await chunked(ids) { chunk in
            try await self.db.from("profiles").select().in("id", values: chunk).execute().value
        }
    }

    /// Profile ids are read-only on the server, so this updates without the
    /// id and inserts only when there's no row yet (an upsert would try to
    /// write the id and be refused).
    public func saveProfile(_ draft: ProfileDraft) async throws -> ProfileRow {
        struct Patch: Encodable {
            let username: String, display_name: String, avatar_path: String?, sports: [Sport], home_courts: [CourtTag]
        }
        let patch = Patch(username: draft.username, display_name: draft.displayName, avatar_path: draft.avatarPath,
                          sports: draft.sports, home_courts: draft.homeCourts)
        let updated: [ProfileRow] = try await db.from("profiles").update(patch).eq("id", value: draft.id)
            .select().execute().value
        if let row = updated.first { return row }
        return try await db.from("profiles").insert(draft).select().single().execute().value
    }

    public func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await db.rpc("username_available", params: ["name": username]).execute().value
    }

    public func searchUsers(_ query: String) async throws -> [ProfileCard] {
        try await db.rpc("search_users", params: ["query": query]).execute().value
    }

    public func players(ids: [UUID]) async throws -> [PlayerRow] {
        try await chunked(ids) { chunk in
            try await self.db.from("players").select().in("id", values: chunk).execute().value
        }
    }

    // MARK: Friends

    public func friendships() async throws -> [FriendshipRow] {
        try await db.from("friendships").select().execute().value
    }

    public func requestFriend(_ userID: UUID) async throws -> FriendshipRow.Status {
        let status: String = try await db.rpc("request_friend", params: ["target": userID]).execute().value
        return FriendshipRow.Status(rawValue: status) ?? .pending
    }

    public func respondToFriendRequest(from userID: UUID, accept: Bool) async throws {
        struct Params: Encodable { let requester: UUID; let accept: Bool }
        try await db.rpc("respond_friend", params: Params(requester: userID, accept: accept)).execute()
    }

    public func removeFriend(_ userID: UUID) async throws {
        let me = try me()
        let (a, b) = Self.canonical(me, userID)
        try await db.from("friendships").delete().eq("user_a", value: a).eq("user_b", value: b).execute()
    }

    public func blockedUsers() async throws -> [UUID] {
        let rows: [BlockRow] = try await db.from("blocks").select().execute().value
        return rows.map(\.blocked)
    }

    public func block(_ userID: UUID) async throws {
        try await db.rpc("block_user", params: ["target": userID]).execute()
    }

    public func unblock(_ userID: UUID) async throws {
        try await db.from("blocks").delete().eq("blocker", value: try me()).eq("blocked", value: userID).execute()
    }

    public func report(_ report: ReportDraft) async throws {
        try await db.from("reports").insert(report).execute()
    }

    public func createInvite(_ kind: InviteKind, target: UUID?) async throws -> InviteLink {
        struct Params: Encodable { let invite_kind: InviteKind; let target: UUID? }
        let token: String = try await db.rpc("create_invite", params: Params(invite_kind: kind, target: target)).execute().value
        guard let link = InviteLink(token: token) else { throw BackendError.unexpected("bad invite token") }
        return link
    }

    public func redeemInvite(_ link: InviteLink) async throws -> InviteRedemption {
        try await db.rpc("redeem_invite", params: ["tok": link.token]).execute().value
    }

    // MARK: Squads

    public func squads() async throws -> [SquadRow] {
        try await db.from("squads").select().order("created_at").execute().value
    }

    public func squadMembers() async throws -> [SquadMemberRow] {
        try await db.from("squad_members").select().execute().value
    }

    public func createSquad(name: String, members: [UUID]) async throws -> UUID {
        struct Params: Encodable { let squad_name: String; let member_ids: [UUID] }
        return try await db.rpc("create_squad", params: Params(squad_name: name, member_ids: members)).execute().value
    }

    public func addSquadMember(_ userID: UUID, to squadID: UUID) async throws {
        try await db.rpc("add_squad_member", params: ["sid": squadID, "member": userID]).execute()
    }

    public func leaveSquad(_ squadID: UUID) async throws {
        try await db.from("squad_members").delete().eq("squad_id", value: squadID).eq("user_id", value: try me()).execute()
    }

    public func updateSquad(_ squadID: UUID, name: String?, signatureChant: [Chant.Beat]?) async throws {
        var patch: [String: JSONValue] = [:]
        if let name { patch["name"] = .string(name) }
        if let signatureChant { patch["signature_chant"] = try JSONValue(encoding: signatureChant) }
        guard !patch.isEmpty else { return }
        try await db.from("squads").update(JSONValue.object(patch), returning: .minimal).eq("id", value: squadID).execute()
    }

    // MARK: Chats

    public func conversations() async throws -> [ConversationRow] {
        try await db.from("conversations").select().order("last_message_at", ascending: false, nullsFirst: false).execute().value
    }

    /// Without `after`: the newest `limit` messages. With `after`: every
    /// message since then, oldest first, page by page, so a long time away
    /// never leaves a gap.
    public func messages(in conversationID: UUID, after: Date?, limit: Int) async throws -> [MessageRow] {
        guard let after else {
            let newestFirst: [Lossy<MessageRow>] = try await db.from("messages").select()
                .eq("conversation_id", value: conversationID)
                .order("created_at", ascending: false).order("id", ascending: false)
                .limit(limit).execute().value
            return newestFirst.compactMap(\.value).reversed()
        }
        return try await drain(page: max(limit, 100)) { from, to in
            try await self.db.from("messages").select()
                .eq("conversation_id", value: conversationID)
                .gt("created_at", value: WireCoding.format(after))
                .order("created_at").order("id")
                .range(from: from, to: to).execute().value
        }
    }

    /// Older history: the `limit` messages before `before`, oldest first.
    public func messages(in conversationID: UUID, before: Date, limit: Int) async throws -> [MessageRow] {
        let newestFirst: [Lossy<MessageRow>] = try await db.from("messages").select()
            .eq("conversation_id", value: conversationID)
            .lt("created_at", value: WireCoding.format(before))
            .order("created_at", ascending: false).order("id", ascending: false)
            .limit(limit).execute().value
        return newestFirst.compactMap(\.value).reversed()
    }

    /// Ids of messages in a conversation still visible to me, to drop ones
    /// that were deleted, moderated or hidden by a block.
    public func messageIDs(in conversationID: UUID, since: Date) async throws -> Set<UUID> {
        struct IDRow: Decodable { let id: UUID }
        let rows: [IDRow] = try await drain(page: 1000) { from, to in
            let page: [Lossy<IDRow>] = try await self.db.from("messages").select("id")
                .eq("conversation_id", value: conversationID)
                .gte("created_at", value: WireCoding.format(since))
                .order("created_at").order("id")
                .range(from: from, to: to).execute().value
            return page
        }
        return Set(rows.map(\.id))
    }

    public func deleteMessage(_ id: UUID) async throws {
        try await db.from("messages").delete().eq("id", value: id).execute()
    }

    // MARK: Matches

    /// Every visible match changed since `updatedSince` (all of them when
    /// nil), page by page. A row the app can't read is skipped rather than
    /// failing the rest.
    public func matches(updatedSince: Date?) async throws -> [MatchRow] {
        try await drain(page: 500) { from, to in
            var query = self.db.from("matches").select()
            if let updatedSince { query = query.gte("updated_at", value: WireCoding.format(updatedSince)) }
            return try await query.order("updated_at").order("id").range(from: from, to: to).execute().value
        }
    }

    public func participants(matchIDs: [UUID]) async throws -> [ParticipantRow] {
        try await chunked(matchIDs) { chunk in
            try await self.db.from("match_participants").select().in("match_id", values: chunk).execute().value
        }
    }

    public func withdrawMatch(_ id: UUID) async throws {
        try await db.rpc("withdraw_match", params: ["mid": id]).execute()
    }

    // MARK: Call outs

    public func callOuts() async throws -> [CallOutRow] {
        let rows: [Lossy<CallOutRow>] = try await db.from("callouts").select()
            .order("created_at", ascending: false).limit(200).execute().value
        return rows.compactMap(\.value)
    }

    public func createCallOut(_ draft: CallOutDraft) async throws -> UUID {
        struct Params: Encodable { let c: CallOutDraft }
        return try await db.rpc("create_callout", params: Params(c: draft)).execute().value
    }

    public func respondToCallOut(_ id: UUID, move: CallOut.Move) async throws -> CallOut.Status {
        struct Params: Encodable { let cid: UUID; let response: String; let counter_offer: CallOutRow.Counter? }
        let params: Params
        switch move {
        case .accept: params = Params(cid: id, response: "accept", counter_offer: nil)
        case .decline: params = Params(cid: id, response: "decline", counter_offer: nil)
        case .cancel: params = Params(cid: id, response: "cancel", counter_offer: nil)
        case .counter(let terms):
            params = Params(cid: id, response: "counter", counter_offer: .init(proposedAt: terms.proposedAt, court: terms.court))
        }
        let status: String = try await db.rpc("respond_callout", params: params).execute().value
        return CallOut.Status(rawValue: status) ?? .pending
    }

    // MARK: Tournaments

    public func tournaments() async throws -> [TournamentRow] {
        let rows: [Lossy<TournamentRow>] = try await db.from("tournaments").select()
            .order("created_at", ascending: false).execute().value
        return rows.compactMap(\.value)
    }

    public func entrants(tournamentIDs: [UUID]) async throws -> [EntrantRow] {
        try await chunked(tournamentIDs) { chunk in
            try await self.db.from("tournament_entrants").select().in("tournament_id", values: chunk).execute().value
        }
    }

    public func fixtures(tournamentIDs: [UUID]) async throws -> [FixtureRow] {
        try await chunked(tournamentIDs) { chunk in
            try await self.db.from("tournament_fixtures").select().in("tournament_id", values: chunk)
                .order("round").order("court_number").execute().value
        }
    }

    public func createTournament(_ draft: TournamentDraft) async throws -> UUID {
        try await db.rpc("create_tournament", params: draft).execute().value
    }

    public func scheduleFixture(_ id: UUID, at date: Date?, court: CourtTag?) async throws {
        let patch: JSONValue = .object([
            "scheduled_at": date.map { .string(WireCoding.format($0)) } ?? .null,
            "court": try court.map { try JSONValue(encoding: $0) } ?? .null
        ])
        try await db.from("tournament_fixtures").update(patch, returning: .minimal).eq("id", value: id).execute()
    }

    public func addFixtures(_ fixtures: [FixtureRow]) async throws {
        guard !fixtures.isEmpty else { return }
        // Another phone may have added the same bracket match a moment ago.
        try await db.from("tournament_fixtures")
            .upsert(fixtures, onConflict: "tournament_id,stage,round,slot", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }

    public func completeTournament(_ id: UUID, champions: [UUID]) async throws {
        struct Params: Encodable { let tid: UUID; let champion_ids: [UUID] }
        try await db.rpc("complete_tournament", params: Params(tid: id, champion_ids: champions)).execute()
    }

    public func trophies(ownerIDs: [UUID]) async throws -> [TrophyRow] {
        try await chunked(ownerIDs) { chunk in
            try await self.db.from("trophies").select().in("owner_id", values: chunk).order("awarded_at", ascending: false).execute().value
        }
    }

    // MARK: Replays

    public func replays() async throws -> [ReplayRow] {
        let rows: [Lossy<ReplayRow>] = try await db.from("replays").select()
            .order("created_at", ascending: false).limit(200).execute().value
        return rows.compactMap(\.value)
    }

    public func createReplay(_ replay: ReplayRow) async throws {
        struct Draft: Encodable {
            let id: UUID, match_id: UUID, author_id: UUID, story: ReplayStory, photo_paths: [String]
        }
        try await db.from("replays").insert(
            Draft(id: replay.id, match_id: replay.matchID, author_id: replay.authorID, story: replay.story, photo_paths: replay.photoPaths),
            returning: .minimal
        ).execute()
    }

    public func shareReplay(_ id: UUID, to conversationID: UUID) async throws {
        try await db.rpc("share_replay", params: ["rid": id, "conversation": conversationID]).execute()
    }

    public func saveReplay(_ id: UUID, title: String) async throws {
        struct Params: Encodable { let rid: UUID; let title: String }
        try await db.rpc("save_replay", params: Params(rid: id, title: title)).execute()
    }

    // MARK: Feed

    public func feed() async throws -> [ServeRow] {
        let rows: [Lossy<ServeRow>] = try await db.from("feed_serves").select()
            .order("created_at", ascending: false).limit(300).execute().value
        return rows.compactMap(\.value)
    }

    public func serves(by authorID: UUID) async throws -> [ServeRow] {
        try await db.from("serves").select().eq("author_id", value: authorID).order("created_at", ascending: false).limit(100).execute().value
    }

    public func createServe(_ draft: ServeDraft) async throws {
        try await db.from("serves").insert(draft, returning: .minimal).execute()
    }

    public func deleteServe(_ id: UUID) async throws {
        try await db.from("serves").delete().eq("id", value: id).execute()
    }

    public func returns(serveIDs: [UUID]) async throws -> [ReturnRow] {
        try await chunked(serveIDs) { chunk in
            try await self.db.from("returns").select().in("serve_id", values: chunk).order("created_at").execute().value
        }
    }

    public func deleteReturn(_ id: UUID) async throws {
        try await db.from("returns").delete().eq("id", value: id).execute()
    }

    // MARK: Live matches

    public func liveMatches() async throws -> [LiveMatchRow] {
        let rows: [Lossy<LiveMatchRow>] = try await db.from("live_matches").select()
            .order("started_at", ascending: false).execute().value
        return rows.compactMap(\.value)
    }

    public func publishLive(_ live: LiveMatchRow) async throws {
        struct Row: Encodable {
            let match_id: UUID, host_id: UUID, sport: Sport, player_ids: [UUID], lineup: Lineup, score: LiveScoreSnapshot, squad_id: UUID?
        }
        // The match and host ids are read-only once published: update the
        // rest, and insert only the first time.
        struct Patch: Encodable {
            let sport: Sport, player_ids: [UUID], lineup: Lineup, score: LiveScoreSnapshot, squad_id: UUID?
        }
        struct IDRow: Decodable { let match_id: UUID }
        let patch = Patch(sport: live.sport, player_ids: live.playerIDs, lineup: live.lineup, score: live.score,
                          squad_id: live.squadID)
        let updated: [IDRow] = try await db.from("live_matches").update(patch).eq("match_id", value: live.matchID)
            .select("match_id").execute().value
        guard updated.isEmpty else { return }
        let row = Row(match_id: live.matchID, host_id: live.hostID, sport: live.sport, player_ids: live.playerIDs,
                      lineup: live.lineup, score: live.score, squad_id: live.squadID)
        try await db.from("live_matches").insert(row, returning: .minimal).execute()
    }

    public func endLive(_ matchID: UUID) async throws {
        try await db.from("live_matches").delete().eq("match_id", value: matchID).execute()
    }

    // MARK: Media

    public func upload(_ data: Data, to bucket: MediaBucket, path: String, contentType: String) async throws -> String {
        try await client.storage.from(bucket.rawValue).upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))
        return path
    }

    public func url(for path: String, in bucket: MediaBucket) async throws -> URL {
        switch bucket {
        case .avatars:
            return try client.storage.from(bucket.rawValue).getPublicURL(path: path)
        case .media:
            if let cached = await urlCache.url(for: path) { return cached }
            let url = try await client.storage.from(bucket.rawValue).createSignedURL(path: path, expiresIn: 3600)
            await urlCache.store(url, for: path, validFor: 50 * 60)
            return url
        }
    }

    /// Public bucket URL, built locally (profile photos).
    public func publicURL(for path: String, in bucket: MediaBucket) -> URL? {
        try? client.storage.from(bucket.rawValue).getPublicURL(path: path)
    }

    public func removeMedia(_ paths: [String], from bucket: MediaBucket) async throws {
        guard !paths.isEmpty else { return }
        _ = try await client.storage.from(bucket.rawValue).remove(paths: paths)
    }

    // MARK: Account

    /// Deletes the signed-in account. Prefers the delete-account Edge
    /// Function (files removed with full rights, Sign in with Apple
    /// revoked); falls back to doing what the app can itself when the
    /// function isn't deployed.
    public func deleteAccount(appleAuthorizationCode: String?) async throws -> AccountDeletion {
        _ = try me()
        struct Body: Encodable { let appleAuthorizationCode: String? }
        do {
            let result: AccountDeletion = try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: Body(appleAuthorizationCode: appleAuthorizationCode))
            )
            guard result.ok else { throw BackendError.unexpected(result.error ?? "deletion failed") }
            try? await client.auth.signOut(scope: .local)
            return result
        } catch FunctionsError.httpError(let code, _) where code == 404 {
            return try await deleteAccountFromDevice()
        } catch FunctionsError.relayError {
            return try await deleteAccountFromDevice()
        }
    }

    /// Fallback: the app removes its own files (page by page), then the data.
    private func deleteAccountFromDevice() async throws -> AccountDeletion {
        let me = try me()
        var removed = 0
        for bucket in [MediaBucket.avatars, .media] {
            let paths = try await allFiles(in: bucket, under: me.uuidString.lowercased())
            for start in stride(from: 0, to: paths.count, by: 100) {
                try await removeMedia(Array(paths[start..<min(start + 100, paths.count)]), from: bucket)
            }
            removed += paths.count
        }
        try await db.rpc("delete_account").execute()
        try? await client.auth.signOut(scope: .local)
        return AccountDeletion(ok: true, filesRemoved: removed, appleRevoked: false, error: nil)
    }

    private func allFiles(in bucket: MediaBucket, under folder: String) async throws -> [String] {
        var paths: [String] = []
        var queue = [folder]
        while let current = queue.popLast() {
            var entries: [FileObject] = []
            var offset = 0
            while true {
                let page = try await client.storage.from(bucket.rawValue)
                    .list(path: current, options: SearchOptions(limit: 100, offset: offset))
                entries += page
                if page.count < 100 { break }
                offset += 100
            }
            for entry in entries {
                let path = "\(current)/\(entry.name)"
                // Folders come back without an id.
                if entry.id == nil { queue.append(path) } else { paths.append(path) }
            }
        }
        return paths
    }

    // MARK: Outbox transport

    public func send(_ operation: OutboxOperation) async -> OutboxOutcome {
        guard client.auth.currentUser != nil else { return .retry("signed out") }
        do {
            switch operation.action {
            case .rpc(let name, let params):
                try await db.rpc(name, params: params).execute()
            case .insert(let table, let row):
                try await db.from(table).insert(row, returning: .minimal).execute()
            }
            return .sent
        } catch {
            return Self.outcome(for: error)
        }
    }

    /// Network trouble and expired sessions retry; anything the database
    /// refused is final. A duplicate insert means an earlier attempt landed.
    static func outcome(for error: Error) -> OutboxOutcome {
        if let error = error as? PostgrestError {
            if error.code == "23505" { return .sent }
            if error.code?.hasPrefix("PGRST3") == true { return .retry(error.message) }
            return .rejected(error.message)
        }
        if let error = error as? HTTPError {
            let status = error.response.statusCode
            if status >= 500 || status == 401 || status == 408 || status == 429 { return .retry("HTTP \(status)") }
            return .rejected("HTTP \(status)")
        }
        if error is URLError || error is CancellationError { return .retry(error.localizedDescription) }
        return .retry(String(describing: error))
    }

    // MARK: Helpers

    static func canonical(_ a: UUID, _ b: UUID) -> (UUID, UUID) {
        // Postgres orders uuids byte-wise, which lowercase hex preserves.
        a.uuidString.lowercased() < b.uuidString.lowercased() ? (a, b) : (b, a)
    }

    /// `in.(…)` filters live in the URL; keep each request comfortably short.
    /// Fetches page after page until a short one, skipping rows that
    /// don't decode.
    private func drain<T: Sendable>(page: Int, _ fetch: @Sendable (Int, Int) async throws -> [Lossy<T>]) async throws -> [T] {
        var result: [T] = []
        var from = 0
        while true {
            let rows = try await fetch(from, from + page - 1)
            result += rows.compactMap(\.value)
            if rows.count < page || from >= 50_000 { break }
            from += page
        }
        return result
    }

    private func chunked<T: Sendable>(_ ids: [UUID], _ fetch: @Sendable ([UUID]) async throws -> [T]) async throws -> [T] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }
        var result: [T] = []
        for start in stride(from: 0, to: unique.count, by: 80) {
            result += try await fetch(Array(unique[start..<min(start + 80, unique.count)]))
        }
        return result
    }
}

public enum BackendError: LocalizedError, Sendable {
    case signedOut
    case notConfigured
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .signedOut: return "You’re signed out."
        case .notConfigured: return "This build isn’t connected to a server."
        case .unexpected(let message): return message
        }
    }
}

/// Signed media URLs, reused until shortly before they expire.
actor SignedURLCache {
    private var entries: [String: (url: URL, expires: Date)] = [:]

    func url(for path: String) -> URL? {
        guard let entry = entries[path], entry.expires > Date() else { return nil }
        return entry.url
    }

    func store(_ url: URL, for path: String, validFor seconds: TimeInterval) {
        entries[path] = (url, Date().addingTimeInterval(seconds))
    }
}

#if !canImport(Security)
/// Session storage for platforms without a keychain (Linux CI builds).
final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}
#endif
