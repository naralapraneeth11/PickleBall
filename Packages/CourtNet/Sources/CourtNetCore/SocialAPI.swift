//
//  SocialAPI.swift
//  CourtNetCore
//
//  Everything the app asks of the backend, as one protocol. The Supabase
//  implementation lives in CourtNet; previews and tests use a fake. Row-
//  level security decides what each call can see — nothing here filters
//  for privacy.
//

import Foundation
import CourtKit

public enum MediaBucket: String, Sendable {
    /// Public profile photos.
    case avatars
    /// Friends-only: chat photos, Serves, Returns, Replay photos.
    case media
}

public protocol SocialAPI: OutboxTransport {
    // Profiles
    func profile(id: UUID) async throws -> ProfileRow?
    func profiles(ids: [UUID]) async throws -> [ProfileRow]
    func saveProfile(_ draft: ProfileDraft) async throws -> ProfileRow
    func isUsernameAvailable(_ username: String) async throws -> Bool
    func searchUsers(_ query: String) async throws -> [ProfileCard]
    func players(ids: [UUID]) async throws -> [PlayerRow]

    // Friends, blocks, reports, invites
    func friendships() async throws -> [FriendshipRow]
    func requestFriend(_ userID: UUID) async throws -> FriendshipRow.Status
    func respondToFriendRequest(from userID: UUID, accept: Bool) async throws
    func removeFriend(_ userID: UUID) async throws
    func blockedUsers() async throws -> [UUID]
    func block(_ userID: UUID) async throws
    func unblock(_ userID: UUID) async throws
    func report(_ report: ReportDraft) async throws
    func createInvite(_ kind: InviteKind, target: UUID?) async throws -> InviteLink
    func redeemInvite(_ link: InviteLink) async throws -> InviteRedemption

    // Squads
    func squads() async throws -> [SquadRow]
    func squadMembers() async throws -> [SquadMemberRow]
    func createSquad(name: String, members: [UUID]) async throws -> UUID
    func addSquadMember(_ userID: UUID, to squadID: UUID) async throws
    func leaveSquad(_ squadID: UUID) async throws
    func updateSquad(_ squadID: UUID, name: String?, signatureChant: [Chant.Beat]?) async throws

    // Chats
    func conversations() async throws -> [ConversationRow]
    func messages(in conversationID: UUID, after: Date?, limit: Int) async throws -> [MessageRow]
    func messages(in conversationID: UUID, before: Date, limit: Int) async throws -> [MessageRow]
    func messageIDs(in conversationID: UUID, since: Date) async throws -> Set<UUID>
    func deleteMessage(_ id: UUID) async throws

    // Matches
    func matches(updatedSince: Date?) async throws -> [MatchRow]
    func participants(matchIDs: [UUID]) async throws -> [ParticipantRow]
    func withdrawMatch(_ id: UUID) async throws

    // Call outs
    func callOuts() async throws -> [CallOutRow]
    func createCallOut(_ draft: CallOutDraft) async throws -> UUID
    func respondToCallOut(_ id: UUID, move: CallOut.Move) async throws -> CallOut.Status

    // Squad tournaments and trophies
    func tournaments() async throws -> [TournamentRow]
    func entrants(tournamentIDs: [UUID]) async throws -> [EntrantRow]
    func fixtures(tournamentIDs: [UUID]) async throws -> [FixtureRow]
    func createTournament(_ draft: TournamentDraft) async throws -> UUID
    func scheduleFixture(_ id: UUID, at date: Date?, court: CourtTag?) async throws
    func addFixtures(_ fixtures: [FixtureRow]) async throws
    func completeTournament(_ id: UUID, champions: [UUID]) async throws
    func trophies(ownerIDs: [UUID]) async throws -> [TrophyRow]

    // Replays
    func replays() async throws -> [ReplayRow]
    func createReplay(_ replay: ReplayRow) async throws
    func shareReplay(_ id: UUID, to conversationID: UUID) async throws
    func saveReplay(_ id: UUID, title: String) async throws

    // Feed
    func feed() async throws -> [ServeRow]
    func serves(by authorID: UUID) async throws -> [ServeRow]
    func createServe(_ draft: ServeDraft) async throws
    func deleteServe(_ id: UUID) async throws
    func returns(serveIDs: [UUID]) async throws -> [ReturnRow]
    func deleteReturn(_ id: UUID) async throws

    // Live matches (crowd taps travel over Realtime; see CourtNet.LiveChannel)
    func liveMatches() async throws -> [LiveMatchRow]
    func publishLive(_ live: LiveMatchRow) async throws
    func endLive(_ matchID: UUID) async throws

    // Media
    func upload(_ data: Data, to bucket: MediaBucket, path: String, contentType: String) async throws -> String
    func url(for path: String, in bucket: MediaBucket) async throws -> URL
    func removeMedia(_ paths: [String], from bucket: MediaBucket) async throws

    // Account
    func deleteAccount(appleAuthorizationCode: String?) async throws -> AccountDeletion
    func publishLevels(_ levels: [String: Double]) async throws

    // Watch and share
    func createShareLink(_ kind: ShareLinkKind, target: UUID) async throws -> String

    // Moderation (admins only; the server checks)
    func isAdmin() async throws -> Bool
    func adminReports(openOnly: Bool) async throws -> [AdminReportRow]
    func adminResolve(_ reportID: UUID, _ resolution: ReportResolution) async throws
    func adminBans() async throws -> [AdminBanRow]
    func adminBan(_ userID: UUID, reason: String) async throws
    func adminUnban(_ userID: UUID) async throws
    func adminStats() async throws -> AdminStats

    // Launch numbers (no account needed)
    func ping(_ ping: PingDraft) async throws
    func reportCrash(_ crash: CrashDraft) async throws
}

/// Everything create_tournament takes.
public struct TournamentDraft: Codable, Hashable, Sendable {
    public struct Info: Codable, Hashable, Sendable {
        public var squadID: UUID
        public var name: String
        public var sport: Sport
        public var format: TournamentFormat
        public var rules: MatchRules
        public var settings: TournamentSettings

        enum CodingKeys: String, CodingKey {
            case name, sport, format, rules, settings
            case squadID = "squad_id"
        }
    }

    public struct Entrant: Codable, Hashable, Sendable {
        public var playerID: UUID
        public var kind: PlayerKind
        public var displayName: String

        enum CodingKeys: String, CodingKey {
            case kind
            case playerID = "player_id"
            case displayName = "display_name"
        }
    }

    public var t: Info
    public var entrants: [Entrant]
    public var fixtures: [FixtureRow]

    public init(squadID: UUID, name: String, format: TournamentFormat, rules: MatchRules, entrants: [PlayerRef], fixtures: [Fixture],
                settings: TournamentSettings = TournamentSettings()) {
        self.t = Info(squadID: squadID, name: name, sport: rules.sport, format: format, rules: rules, settings: settings)
        self.entrants = entrants.map { Entrant(playerID: $0.id.rawValue, kind: $0.kind, displayName: $0.displayName) }
        // The tournament id is assigned by the server; fixtures carry a
        // placeholder that create_tournament ignores.
        self.fixtures = fixtures.map { FixtureRow($0, tournamentID: Self.placeholder) }
    }

    static let placeholder = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

/// What deleting an account did.
public struct AccountDeletion: Codable, Hashable, Sendable {
    public var ok: Bool
    public var filesRemoved: Int
    /// Nil when no Apple code was sent; false when revoking failed or the
    /// server function wasn't available.
    public var appleRevoked: Bool?
    public var error: String?

    public init(ok: Bool, filesRemoved: Int, appleRevoked: Bool?, error: String? = nil) {
        self.ok = ok
        self.filesRemoved = filesRemoved
        self.appleRevoked = appleRevoked
        self.error = error
    }
}
