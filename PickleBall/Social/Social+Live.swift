//
//  Social+Live.swift
//  PickleBall
//
//  Live matches for friends: while a Watch- or phone-scored match is on,
//  the owner's phone keeps a live_matches row fresh so friends can follow
//  the score, and listens on the match's crowd channel so their taps reach
//  the players' wrists. Friends following along send taps from the same
//  channel.
//

import Foundation
import CourtKit
import CourtNet

struct SharePrompt: Identifiable {
    let id = UUID()
    let content: ShareCardContent
}

extension Social {
    // MARK: Hosting

    func goLive(_ match: LiveMatch) {
        guard phase == .ready, let backend else { return }
        lastLivePublish = .distantPast
        updateLive(match)

        hostCrowdTask?.cancel()
        let channel = CrowdChannel(backend: backend, matchID: match.id)
        hostCrowd = channel
        let squadChant = squad(match.context.squadID)?.signatureChant
        let squadName = squad(match.context.squadID)?.name ?? "Squad"
        hostCrowdTask = Task { [weak self] in
            let taps = await channel.join()
            for await tap in taps {
                guard let self, !self.blocked.contains(tap.from.rawValue) else { continue }
                let chant: Chant
                if tap.chantID == "squad", let beats = squadChant {
                    chant = .signature(squadName: squadName, beats: beats)
                } else {
                    chant = Chant.preset(id: tap.chantID) ?? .clapClap
                }
                MatchCenter.shared.receiveCrowd(tap, chant: chant)
            }
        }
    }

    /// Publishes the score, at most every few seconds.
    func updateLive(_ match: LiveMatch) {
        guard phase == .ready, let userID else { return }
        let row = LiveMatchRow(matchID: match.id, hostID: userID, sport: match.sport, lineup: match.lineup,
                               score: LiveScoreSnapshot(scorer: match.scorer), squadID: match.context.squadID,
                               startedAt: match.setup.startedAt)
        let wait = max(0, 3 - Date().timeIntervalSince(lastLivePublish))
        liveUpdateTask?.cancel()
        liveUpdateTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            self.lastLivePublish = Date()
            await self.run { try await $0.publishLive(row) }
        }
    }

    func endLive(_ matchID: UUID) {
        liveUpdateTask?.cancel()
        hostCrowdTask?.cancel()
        let channel = hostCrowd
        hostCrowd = nil
        guard phase == .ready, let backend else { return }
        Task {
            await channel?.leave()
            try? await backend.endLive(matchID)
        }
    }

    // MARK: Following a friend's match

    func follow(_ live: LiveMatchRow) async {
        guard let backend else { return }
        await stopFollowing()
        let channel = CrowdChannel(backend: backend, matchID: live.matchID)
        spectatorCrowd = channel
        _ = await channel.join()
    }

    func sendTap(chantID: String, to live: LiveMatchRow) async {
        guard let userID, let channel = spectatorCrowd else { return }
        await channel.send(CrowdTap(matchID: live.matchID, from: PlayerID(rawValue: userID),
                                    fromName: profile?.displayName ?? "A friend", chantID: chantID))
    }

    func stopFollowing() async {
        await spectatorCrowd?.leave()
        spectatorCrowd = nil
    }

    /// The squad chant I can send in a friend's match, if we share a squad.
    func signatureChant(for live: LiveMatchRow) -> Chant? {
        guard let squadID = live.squadID ?? sharedSquad(for: live.lineup.allPlayers.map(\.id))?.id,
              let squad = squad(squadID), let beats = squad.signatureChant,
              members(of: squadID).contains(userID ?? UUID()) else { return nil }
        return .signature(squadName: squad.name, beats: beats)
    }

    // MARK: Share prompts

    /// Offers a share card after a belt win, a big comeback or a trophy.
    func offerShareCard(for result: MatchResult, beltEvents: [BeltEvent], drama: DramaReport?) {
        guard let userID else { return }
        if let content = ShareCards.prompt(for: PlayerID(rawValue: userID), result: result, beltEvents: beltEvents, drama: drama) {
            sharePrompt = SharePrompt(content: content)
        }
    }

    func offerTrophyCard(tournamentName: String) {
        guard let profile else { return }
        sharePrompt = SharePrompt(content: ShareCards.trophy(winnerName: profile.displayName, tournamentName: tournamentName))
    }
}
