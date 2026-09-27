//
//  Social+Friends.swift
//  PickleBall
//
//  Friends, requests, invites, blocks and reports; squads; chat helpers;
//  call outs.
//

import Foundation
import CourtKit
import CourtNet

enum Relationship: Equatable {
    case me
    case friend
    /// They asked; I haven't answered.
    case incoming
    /// I asked; they haven't answered.
    case outgoing
    case blocked
    case none
}

extension Social {
    // MARK: Friends

    var friends: [ProfileRow] {
        guard let userID else { return [] }
        return friendships
            .filter { $0.status == .accepted }
            .map { $0.other(than: userID) }
            .filter { !blocked.contains($0) }
            .compactMap { profiles[$0] }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var friendIDs: Set<UUID> { Set(friends.map(\.id)) }

    var incomingRequests: [ProfileRow] {
        guard let userID else { return [] }
        return friendships
            .filter { $0.status == .pending && $0.requestedBy != userID }
            .compactMap { profiles[$0.other(than: userID)] }
    }

    var outgoingRequests: [ProfileRow] {
        guard let userID else { return [] }
        return friendships
            .filter { $0.status == .pending && $0.requestedBy == userID }
            .compactMap { profiles[$0.other(than: userID)] }
    }

    func relationship(with id: UUID) -> Relationship {
        guard let userID else { return .none }
        if id == userID { return .me }
        if blocked.contains(id) { return .blocked }
        guard let row = friendships.first(where: { $0.other(than: userID) == id && ($0.userA == userID || $0.userB == userID) }) else {
            return .none
        }
        if row.status == .accepted { return .friend }
        return row.requestedBy == userID ? .outgoing : .incoming
    }

    /// Best name we have for an account or player.
    func name(of id: UUID) -> String {
        if id == userID, let profile { return profile.displayName }
        if let profile = profiles[id] { return profile.displayName }
        if let player = players[id] { return player.displayName }
        return PlayerDirectory.shared.player(PlayerID(rawValue: id))?.displayName ?? "Player"
    }

    func firstName(of id: UUID) -> String {
        let full = name(of: id)
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    func playerRef(for id: UUID) -> PlayerRef {
        if let player = players[id], player.kind == .guest, player.claimedBy == nil {
            return PlayerRef(id: PlayerID(rawValue: id), kind: .guest, displayName: player.displayName)
        }
        if let known = PlayerDirectory.shared.player(PlayerID(rawValue: id)), known.kind == .guest {
            return known
        }
        return PlayerRef(id: PlayerID(rawValue: id), kind: .user, displayName: name(of: id))
    }

    /// Friends become players you can pick for a match, on the phone and
    /// the Watch.
    func syncFriendsIntoDirectory() {
        PlayerDirectory.shared.upsertFriends(friends.map { PlayerRef(id: PlayerID(rawValue: $0.id), kind: .user, displayName: $0.displayName) })
    }

    func search(_ query: String) async -> [ProfileCard] {
        let q = Username.normalize(query)
        guard q.count >= 2, let backend else { return [] }
        return (try? await backend.searchUsers(q)) ?? []
    }

    func requestFriend(_ id: UUID) async {
        await run { _ = try await $0.requestFriend(id) }
        await refreshFriends()
    }

    func respondToRequest(from id: UUID, accept: Bool) async {
        await run { try await $0.respondToFriendRequest(from: id, accept: accept) }
        await refreshFriends()
        if accept { await refreshSquadsAndChats() }
    }

    func removeFriend(_ id: UUID) async {
        await run { try await $0.removeFriend(id) }
        await refreshFriends()
    }

    func block(_ id: UUID) async {
        guard await run({ try await $0.block(id) }) else { return }
        var ids = blocked
        ids.insert(id)
        setBlocked(ids)
        setFeed(feed.filter { $0.authorID != id })
        await refreshFriends()
        await refreshSquadsAndChats()
    }

    func unblock(_ id: UUID) async {
        guard await run({ try await $0.unblock(id) }) else { return }
        var ids = blocked
        ids.remove(id)
        setBlocked(ids)
    }

    func report(_ target: ReportDraft.Target, id: UUID, reason: String) async -> Bool {
        guard let userID else { return false }
        let ok = await run { try await $0.report(ReportDraft(reporter: userID, targetType: target, targetID: id, reason: reason)) }
        if ok { notice = "Thanks. We’ll take a look." }
        return ok
    }

    // MARK: Invites

    func inviteLink(_ kind: InviteKind, target: UUID? = nil) async -> InviteLink? {
        var link: InviteLink?
        await run { link = try await $0.createInvite(kind, target: target) }
        return link
    }

    func shareURL(for link: InviteLink) -> URL {
        link.shareURL(page: invitePage)
    }

    /// Opens an invite (from a link, a QR code or a typed code).
    @discardableResult
    func redeem(_ link: InviteLink) async -> InviteRedemption? {
        var result: InviteRedemption?
        guard await run({ result = try await $0.redeemInvite(link) }) else { return nil }
        switch result?.kind {
        case .friend?: notice = "You’re friends now."
        case .squad?: notice = "You joined the squad."
        case .guestClaim?: notice = "Those matches are yours now."
        case nil: break
        }
        await refreshFriends()
        await refreshSquadsAndChats()
        if result?.kind == .guestClaim { await refreshMatches() }
        return result
    }

    // MARK: Squads

    func members(of squadID: UUID) -> [UUID] {
        squadMembers.filter { $0.squadID == squadID }.map(\.userID)
    }

    func squad(_ id: UUID?) -> SquadRow? {
        guard let id else { return nil }
        return squads.first { $0.id == id }
    }

    func squadConversation(_ squadID: UUID) -> ConversationRow? {
        conversations.first { $0.squadID == squadID }
    }

    /// The squad every player in a lineup belongs to, if exactly one fits.
    func sharedSquad(for players: [PlayerID]) -> SquadRow? {
        let users = Set(players.map(\.rawValue)).filter { playerUser($0) != nil }
        guard users.count >= 2 else { return nil }
        let fits = squads.filter { squad in users.isSubset(of: Set(members(of: squad.id))) }
        return fits.count == 1 ? fits[0] : nil
    }

    func createSquad(name: String, members: [UUID]) async -> UUID? {
        guard let cleaned = ContentFilter.standard.cleaned(name.trimmingCharacters(in: .whitespacesAndNewlines)), !cleaned.isEmpty else {
            notice = "Pick a different squad name."
            return nil
        }
        var id: UUID?
        await run { id = try await $0.createSquad(name: cleaned, members: members) }
        await refreshSquadsAndChats()
        return id
    }

    func addToSquad(_ squadID: UUID, friend: UUID) async {
        await run { try await $0.addSquadMember(friend, to: squadID) }
        await refreshSquadsAndChats()
    }

    func leaveSquad(_ squadID: UUID) async {
        await run { try await $0.leaveSquad(squadID) }
        await refreshSquadsAndChats()
    }

    func renameSquad(_ squadID: UUID, to name: String) async {
        guard let cleaned = ContentFilter.standard.cleaned(name), !cleaned.isEmpty else { return }
        await run { try await $0.updateSquad(squadID, name: cleaned, signatureChant: nil) }
        await refreshSquadsAndChats()
    }

    func setSignatureChant(_ squadID: UUID, beats: [Chant.Beat]) async {
        await run { try await $0.updateSquad(squadID, name: nil, signatureChant: beats) }
        await refreshSquadsAndChats()
    }

    // MARK: Chats

    func directConversation(with friendID: UUID) -> ConversationRow? {
        conversations.first { $0.kind == .direct && ($0.userA == friendID || $0.userB == friendID) }
    }

    func title(of conversation: ConversationRow) -> String {
        switch conversation.kind {
        case .squad: return squad(conversation.squadID)?.name ?? "Squad"
        case .direct: return userID.flatMap(conversation.friend(of:)).map(name(of:)) ?? "Chat"
        }
    }

    /// Everyone in a chat besides me.
    func people(in conversation: ConversationRow) -> [UUID] {
        switch conversation.kind {
        case .squad: return conversation.squadID.map(members(of:))?.filter { $0 != userID } ?? []
        case .direct: return userID.flatMap(conversation.friend(of:)).map { [$0] } ?? []
        }
    }

    func deleteMessage(_ message: MessageRow) async {
        guard await run({ try await $0.deleteMessage(message.id) }) else { return }
        removeMessage(message.id, from: message.conversationID)
    }

    // MARK: Call outs

    /// Call outs I'm in that are still open or agreed, newest first.
    var activeCallOuts: [CallOutRow] {
        callOuts.filter { $0.status.isActive }
    }

    /// Open call outs where it's my move.
    var callOutsAwaitingMe: [CallOutRow] {
        guard let userID else { return [] }
        return activeCallOuts.filter { $0.callOut.isTurn(of: PlayerID(rawValue: userID)) }
    }

    func createCallOut(_ draft: CallOutDraft) async -> Bool {
        let ok = await run { _ = try await $0.createCallOut(draft) }
        await refreshCallOuts()
        return ok
    }

    func respond(to callOut: CallOutRow, with move: CallOut.Move) async {
        await run { _ = try await $0.respondToCallOut(callOut.id, move: move) }
        await refreshCallOuts()
    }

    /// A lineup matching a call out, for starting or entering its match.
    func lineup(for callOut: CallOutRow) -> Lineup {
        Lineup(teamA: callOut.challengers.map(playerRef(for:)), teamB: callOut.challenged.map(playerRef(for:)))
    }
}
