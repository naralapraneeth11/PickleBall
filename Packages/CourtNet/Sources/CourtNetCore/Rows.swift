//
//  Rows.swift
//  CourtNetCore
//
//  One struct per table (or RPC result), spelled exactly like the database
//  in supabase/migrations. Kept dumb on purpose: conversion to CourtKit
//  types lives in MatchWire and the app.
//

import Foundation
import CourtKit

// MARK: - Profiles and players

public struct ProfileRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var avatarPath: String?
    public var sports: [Sport]
    public var homeCourts: [CourtTag]
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, username: String, displayName: String, avatarPath: String? = nil,
                sports: [Sport] = [.pickleball], homeCourts: [CourtTag] = [], createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.sports = sports
        self.homeCourts = homeCourts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, username, sports
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case homeCourts = "home_courts"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// What profile setup writes. Timestamps are the server's.
public struct ProfileDraft: Codable, Hashable, Sendable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var avatarPath: String?
    public var sports: [Sport]
    public var homeCourts: [CourtTag]

    public init(id: UUID, username: String, displayName: String, avatarPath: String?, sports: [Sport], homeCourts: [CourtTag]) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.sports = sports
        self.homeCourts = homeCourts
    }

    enum CodingKeys: String, CodingKey {
        case id, username, sports
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case homeCourts = "home_courts"
    }
}

/// A username search hit: just enough to send a friend request.
public struct ProfileCard: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var avatarPath: String?

    public init(id: UUID, username: String, displayName: String, avatarPath: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarPath = avatarPath
    }

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

public struct PlayerRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PlayerKind
    public var displayName: String
    public var createdBy: UUID?
    public var claimedBy: UUID?

    public init(id: UUID, kind: PlayerKind, displayName: String, createdBy: UUID? = nil, claimedBy: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.createdBy = createdBy
        self.claimedBy = claimedBy
    }

    /// The account this player stands for, if any.
    public var userID: UUID? { claimedBy ?? (kind == .user ? id : nil) }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case displayName = "display_name"
        case createdBy = "created_by"
        case claimedBy = "claimed_by"
    }
}

// MARK: - Friends, blocks, reports, invites

public struct FriendshipRow: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, accepted }

    public var userA: UUID
    public var userB: UUID
    public var status: Status
    public var requestedBy: UUID
    public var createdAt: Date?
    public var acceptedAt: Date?

    public init(userA: UUID, userB: UUID, status: Status, requestedBy: UUID, createdAt: Date? = nil, acceptedAt: Date? = nil) {
        self.userA = userA
        self.userB = userB
        self.status = status
        self.requestedBy = requestedBy
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
    }

    public func other(than me: UUID) -> UUID { userA == me ? userB : userA }

    enum CodingKeys: String, CodingKey {
        case status
        case userA = "user_a"
        case userB = "user_b"
        case requestedBy = "requested_by"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
    }
}

public struct BlockRow: Codable, Hashable, Sendable {
    public var blocker: UUID
    public var blocked: UUID

    public init(blocker: UUID, blocked: UUID) {
        self.blocker = blocker
        self.blocked = blocked
    }
}

public struct ReportDraft: Codable, Hashable, Sendable {
    public enum Target: String, Codable, Sendable { case user, message, serve, `return`, replay, match }

    public var reporter: UUID
    public var targetType: Target
    public var targetID: UUID
    public var reason: String

    public init(reporter: UUID, targetType: Target, targetID: UUID, reason: String) {
        self.reporter = reporter
        self.targetType = targetType
        self.targetID = targetID
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case reporter, reason
        case targetType = "target_type"
        case targetID = "target_id"
    }
}

public enum InviteKind: String, Codable, Sendable {
    case friend
    case squad
    case guestClaim = "guest_claim"
}

/// What redeeming an invite did.
public struct InviteRedemption: Codable, Hashable, Sendable {
    public var kind: InviteKind
    public var userID: UUID?
    public var squadID: UUID?
    public var playerID: UUID?

    enum CodingKeys: String, CodingKey {
        case kind
        case userID = "user_id"
        case squadID = "squad_id"
        case playerID = "player_id"
    }
}

// MARK: - Squads

public struct SquadRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdBy: UUID?
    public var signatureChant: [Chant.Beat]?
    public var createdAt: Date?

    public init(id: UUID, name: String, createdBy: UUID? = nil, signatureChant: [Chant.Beat]? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.signatureChant = signatureChant
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case signatureChant = "signature_chant"
        case createdAt = "created_at"
    }
}

public struct SquadMemberRow: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case owner, member }

    public var squadID: UUID
    public var userID: UUID
    public var role: Role
    public var joinedAt: Date?

    public init(squadID: UUID, userID: UUID, role: Role = .member, joinedAt: Date? = nil) {
        self.squadID = squadID
        self.userID = userID
        self.role = role
        self.joinedAt = joinedAt
    }

    enum CodingKeys: String, CodingKey {
        case role
        case squadID = "squad_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

// MARK: - Chat

public struct ConversationRow: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case direct, squad }

    public var id: UUID
    public var kind: Kind
    public var squadID: UUID?
    public var userA: UUID?
    public var userB: UUID?
    public var createdAt: Date?
    public var lastMessageAt: Date?

    public init(id: UUID, kind: Kind, squadID: UUID? = nil, userA: UUID? = nil, userB: UUID? = nil,
                createdAt: Date? = nil, lastMessageAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.squadID = squadID
        self.userA = userA
        self.userB = userB
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
    }

    /// The friend in a direct chat.
    public func friend(of me: UUID) -> UUID? {
        guard kind == .direct else { return nil }
        return userA == me ? userB : userA
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case squadID = "squad_id"
        case userA = "user_a"
        case userB = "user_b"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
    }
}

public struct MessageRow: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, photo, event }

    public var id: UUID
    public var conversationID: UUID
    /// Nil for event messages the server posts.
    public var senderID: UUID?
    public var kind: Kind
    public var body: String?
    public var payload: ChatEvent?
    public var mediaPath: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), conversationID: UUID, senderID: UUID?, kind: Kind, body: String? = nil,
                payload: ChatEvent? = nil, mediaPath: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.kind = kind
        self.body = body
        self.payload = payload
        self.mediaPath = mediaPath
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body, payload
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case mediaPath = "media_path"
        case createdAt = "created_at"
    }
}

// MARK: - Matches

public struct MatchRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var sport: Sport
    public var rules: MatchRules
    public var source: MatchSource
    public var createdBy: UUID?
    public var status: ConfirmationStatus
    public var startedAt: Date
    public var endedAt: Date?
    public var winnerTeam: Team?
    public var matchScore: [Int]
    public var points: [Int]
    public var units: [CompletedUnit]
    /// "ABBA…": the rally log, for Watch- and phone-scored matches.
    public var rallyWinners: String?
    /// Seconds from `startedAt`, one per rally.
    public var rallyOffsets: [Double]?
    public var court: CourtTag?
    public var squadID: UUID?
    public var tournamentID: UUID?
    public var fixtureID: UUID?
    public var calloutID: UUID?
    public var workout: WorkoutReport?
    public var confirmedAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, sport: Sport, rules: MatchRules, source: MatchSource, createdBy: UUID?, status: ConfirmationStatus,
                startedAt: Date, endedAt: Date?, winnerTeam: Team?, matchScore: [Int], points: [Int], units: [CompletedUnit],
                rallyWinners: String? = nil, rallyOffsets: [Double]? = nil, court: CourtTag? = nil, squadID: UUID? = nil,
                tournamentID: UUID? = nil, fixtureID: UUID? = nil, calloutID: UUID? = nil, workout: WorkoutReport? = nil,
                confirmedAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.sport = sport
        self.rules = rules
        self.source = source
        self.createdBy = createdBy
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.winnerTeam = winnerTeam
        self.matchScore = matchScore
        self.points = points
        self.units = units
        self.rallyWinners = rallyWinners
        self.rallyOffsets = rallyOffsets
        self.court = court
        self.squadID = squadID
        self.tournamentID = tournamentID
        self.fixtureID = fixtureID
        self.calloutID = calloutID
        self.workout = workout
        self.confirmedAt = confirmedAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, sport, rules, source, status, points, units, court, workout
        case createdBy = "created_by"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerTeam = "winner_team"
        case matchScore = "match_score"
        case rallyWinners = "rally_winners"
        case rallyOffsets = "rally_offsets"
        case squadID = "squad_id"
        case tournamentID = "tournament_id"
        case fixtureID = "fixture_id"
        case calloutID = "callout_id"
        case confirmedAt = "confirmed_at"
        case updatedAt = "updated_at"
    }
}

public struct ParticipantRow: Codable, Hashable, Sendable {
    public var matchID: UUID
    public var playerID: UUID
    public var team: Team
    public var slot: Int
    public var confirmedAt: Date?
    public var disputedAt: Date?

    public init(matchID: UUID, playerID: UUID, team: Team, slot: Int, confirmedAt: Date? = nil, disputedAt: Date? = nil) {
        self.matchID = matchID
        self.playerID = playerID
        self.team = team
        self.slot = slot
        self.confirmedAt = confirmedAt
        self.disputedAt = disputedAt
    }

    enum CodingKeys: String, CodingKey {
        case team, slot
        case matchID = "match_id"
        case playerID = "player_id"
        case confirmedAt = "confirmed_at"
        case disputedAt = "disputed_at"
    }
}

// MARK: - Call outs

public struct CallOutRow: Codable, Hashable, Sendable, Identifiable {
    public struct Counter: Codable, Hashable, Sendable {
        public var proposedAt: Date?
        public var court: CourtTag?
        public var by: UUID?

        public init(proposedAt: Date?, court: CourtTag?, by: UUID? = nil) {
            self.proposedAt = proposedAt
            self.court = court
            self.by = by
        }

        enum CodingKeys: String, CodingKey {
            case court, by
            case proposedAt = "proposed_at"
        }
    }

    public var id: UUID
    public var createdBy: UUID
    public var challengers: [UUID]
    public var challenged: [UUID]
    public var sport: Sport
    public var rules: MatchRules
    public var proposedAt: Date?
    public var court: CourtTag?
    public var status: CallOut.Status
    public var counter: Counter?
    public var matchID: UUID?
    public var squadID: UUID?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, challengers, challenged, sport, rules, court, status, counter
        case createdBy = "created_by"
        case proposedAt = "proposed_at"
        case matchID = "match_id"
        case squadID = "squad_id"
        case createdAt = "created_at"
    }

    /// The CourtKit model, so the app can show only legal moves.
    public var callOut: CallOut {
        CallOut(
            id: id,
            createdBy: PlayerID(rawValue: createdBy),
            challengers: challengers.map(PlayerID.init(rawValue:)),
            challenged: challenged.map(PlayerID.init(rawValue:)),
            rules: rules,
            terms: .init(proposedAt: proposedAt, court: court),
            squadID: squadID,
            createdAt: createdAt ?? Date(),
            status: status,
            counter: counter.map { .init(proposedAt: $0.proposedAt, court: $0.court) },
            counterBy: counter?.by.map(PlayerID.init(rawValue:)),
            matchID: matchID
        )
    }
}

public struct CallOutDraft: Codable, Hashable, Sendable {
    public var challengers: [UUID]
    public var challenged: [UUID]
    public var sport: Sport
    public var rules: MatchRules
    public var proposedAt: Date?
    public var court: CourtTag?
    public var squadID: UUID?

    public init(challengers: [UUID], challenged: [UUID], rules: MatchRules, proposedAt: Date? = nil, court: CourtTag? = nil, squadID: UUID? = nil) {
        self.challengers = challengers
        self.challenged = challenged
        self.sport = rules.sport
        self.rules = rules
        self.proposedAt = proposedAt
        self.court = court
        self.squadID = squadID
    }

    enum CodingKeys: String, CodingKey {
        case challengers, challenged, sport, rules, court
        case proposedAt = "proposed_at"
        case squadID = "squad_id"
    }
}

// MARK: - Tournaments and trophies

public struct TournamentRow: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case active, completed }

    public var id: UUID
    public var squadID: UUID
    public var name: String
    public var sport: Sport
    public var format: TournamentFormat
    public var rules: MatchRules
    public var status: Status
    public var champions: [UUID]
    public var createdBy: UUID?
    public var createdAt: Date?
    public var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sport, format, rules, status, champions
        case squadID = "squad_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

public struct EntrantRow: Codable, Hashable, Sendable {
    public var tournamentID: UUID
    public var playerID: UUID

    enum CodingKeys: String, CodingKey {
        case tournamentID = "tournament_id"
        case playerID = "player_id"
    }
}

public struct FixtureRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var tournamentID: UUID
    public var round: Int
    public var courtNumber: Int
    public var teamA: [UUID]
    public var teamB: [UUID]
    public var scheduledAt: Date?
    public var court: CourtTag?
    public var matchID: UUID?

    public init(id: UUID, tournamentID: UUID, round: Int, courtNumber: Int, teamA: [UUID], teamB: [UUID],
                scheduledAt: Date? = nil, court: CourtTag? = nil, matchID: UUID? = nil) {
        self.id = id
        self.tournamentID = tournamentID
        self.round = round
        self.courtNumber = courtNumber
        self.teamA = teamA
        self.teamB = teamB
        self.scheduledAt = scheduledAt
        self.court = court
        self.matchID = matchID
    }

    public init(_ fixture: Fixture, tournamentID: UUID) {
        self.init(id: fixture.id, tournamentID: tournamentID, round: fixture.round, courtNumber: fixture.court,
                  teamA: fixture.teams.a.map(\.rawValue), teamB: fixture.teams.b.map(\.rawValue),
                  scheduledAt: fixture.scheduledAt, court: fixture.place)
    }

    public var fixture: Fixture {
        Fixture(id: id, round: round, court: courtNumber,
                teams: TeamPair(a: teamA.map(PlayerID.init(rawValue:)), b: teamB.map(PlayerID.init(rawValue:))),
                scheduledAt: scheduledAt, place: court)
    }

    enum CodingKeys: String, CodingKey {
        case id, round, court
        case tournamentID = "tournament_id"
        case courtNumber = "court_number"
        case teamA = "team_a"
        case teamB = "team_b"
        case scheduledAt = "scheduled_at"
        case matchID = "match_id"
    }
}

public struct TrophyRow: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case tournament, replay }

    public var id: UUID
    public var ownerID: UUID
    public var kind: Kind
    public var title: String
    public var tournamentID: UUID?
    public var replayID: UUID?
    public var awardedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case ownerID = "owner_id"
        case tournamentID = "tournament_id"
        case replayID = "replay_id"
        case awardedAt = "awarded_at"
    }
}

// MARK: - Replays and the Feed

public struct ReplayRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var matchID: UUID
    public var authorID: UUID
    public var story: ReplayStory
    public var photoPaths: [String]
    public var createdAt: Date
    public var expiresAt: Date
    public var saved: Bool

    public init(id: UUID = UUID(), matchID: UUID, authorID: UUID, story: ReplayStory, photoPaths: [String] = [],
                createdAt: Date = Date(), saved: Bool = false) {
        self.id = id
        self.matchID = matchID
        self.authorID = authorID
        self.story = story
        self.photoPaths = photoPaths
        self.createdAt = createdAt
        self.expiresAt = ReplayLifetime.expiresAt(createdAt: createdAt)
        self.saved = saved
    }

    public func isVisible(now: Date = Date()) -> Bool {
        saved || now < expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id, story, saved
        case matchID = "match_id"
        case authorID = "author_id"
        case photoPaths = "photo_paths"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

public struct ServeRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var authorID: UUID
    public var kind: ServeKind
    public var body: String?
    public var mediaPaths: [String]
    public var matchID: UUID?
    public var createdAt: Date
    public var rallyCount: Int
    public var lastReturnAt: Date?

    public init(id: UUID = UUID(), authorID: UUID, kind: ServeKind, body: String?, mediaPaths: [String] = [],
                matchID: UUID? = nil, createdAt: Date = Date(), rallyCount: Int = 0, lastReturnAt: Date? = nil) {
        self.id = id
        self.authorID = authorID
        self.kind = kind
        self.body = body
        self.mediaPaths = mediaPaths
        self.matchID = matchID
        self.createdAt = createdAt
        self.rallyCount = rallyCount
        self.lastReturnAt = lastReturnAt
    }

    public func isInPlay(now: Date = Date()) -> Bool {
        FeedRules.isInPlay(createdAt: createdAt, lastReturnAt: lastReturnAt, now: now)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case authorID = "author_id"
        case mediaPaths = "media_paths"
        case matchID = "match_id"
        case createdAt = "created_at"
        case rallyCount = "rally_count"
        case lastReturnAt = "last_return_at"
    }
}

/// What a new Serve sends (counts and timestamps are the server's).
public struct ServeDraft: Codable, Hashable, Sendable {
    public var id: UUID
    public var authorID: UUID
    public var kind: ServeKind
    public var body: String?
    public var mediaPaths: [String]
    public var matchID: UUID?

    public init(id: UUID = UUID(), authorID: UUID, kind: ServeKind, body: String?, mediaPaths: [String] = [], matchID: UUID? = nil) {
        self.id = id
        self.authorID = authorID
        self.kind = kind
        self.body = body
        self.mediaPaths = mediaPaths
        self.matchID = matchID
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case authorID = "author_id"
        case mediaPaths = "media_paths"
        case matchID = "match_id"
    }
}

public struct ReturnRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var serveID: UUID
    public var authorID: UUID
    public var kind: ReturnKind
    public var body: String?
    public var mediaPath: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), serveID: UUID, authorID: UUID, kind: ReturnKind, body: String? = nil,
                mediaPath: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.serveID = serveID
        self.authorID = authorID
        self.kind = kind
        self.body = body
        self.mediaPath = mediaPath
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case serveID = "serve_id"
        case authorID = "author_id"
        case mediaPath = "media_path"
        case createdAt = "created_at"
    }
}

// MARK: - Live matches

public struct LiveMatchRow: Codable, Hashable, Sendable, Identifiable {
    public var matchID: UUID
    public var hostID: UUID
    public var sport: Sport
    public var playerIDs: [UUID]
    public var lineup: Lineup
    public var score: LiveScoreSnapshot
    public var squadID: UUID?
    public var startedAt: Date?
    public var updatedAt: Date?

    public init(matchID: UUID, hostID: UUID, sport: Sport, lineup: Lineup, score: LiveScoreSnapshot, squadID: UUID? = nil, startedAt: Date? = nil) {
        self.matchID = matchID
        self.hostID = hostID
        self.sport = sport
        self.playerIDs = lineup.allPlayers.filter { $0.kind == .user }.map(\.id.rawValue)
        self.lineup = lineup
        self.score = score
        self.squadID = squadID
        self.startedAt = startedAt
    }

    public var id: UUID { matchID }

    /// A host that stopped updating (phone died, app killed) isn't live.
    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt ?? startedAt ?? now) < 10 * 60
    }

    enum CodingKeys: String, CodingKey {
        case sport, lineup, score
        case matchID = "match_id"
        case hostID = "host_id"
        case playerIDs = "player_ids"
        case squadID = "squad_id"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}
