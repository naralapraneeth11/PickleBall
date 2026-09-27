//
//  ShareCard.swift
//  CourtKit
//
//  Words for cards shared outside the app (Messages, Instagram, anywhere),
//  and when to offer one: after winning a belt, after a trophy, after a big
//  comeback. Offered, never posted automatically.
//
//  Copy uses names, not pronouns, so it is right for everyone.
//

import Foundation

public struct ShareCardContent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case beltWon
        case beltDefended
        case trophy
        case comeback
        case result
    }

    public var kind: Kind
    public var title: String
    public var subtitle: String
    /// The line above the invite link.
    public var callToAction: String
    public var scoreLine: String?
    public var tier: BeltTier?
}

public enum ShareCards {
    public static func beltWon(holderName: String, sport: Sport, scoreLine: String, tier: BeltTier = .plain) -> ShareCardContent {
        ShareCardContent(
            kind: .beltWon,
            title: "New belt holder",
            subtitle: "\(holderName) took the \(sport.displayName.lowercased()) belt",
            callToAction: "Beat \(holderName) and take the belt.",
            scoreLine: scoreLine,
            tier: tier
        )
    }

    public static func beltDefended(holderName: String, sport: Sport, defenses: Int, tier: BeltTier) -> ShareCardContent {
        ShareCardContent(
            kind: .beltDefended,
            title: tier.title,
            subtitle: "\(holderName) · \(defenses) defense\(defenses == 1 ? "" : "s")",
            callToAction: "Beat \(holderName) and take the belt.",
            scoreLine: nil,
            tier: tier
        )
    }

    public static func trophy(winnerName: String, tournamentName: String) -> ShareCardContent {
        ShareCardContent(
            kind: .trophy,
            title: "Champion",
            subtitle: "\(winnerName) won \(tournamentName)",
            callToAction: "Next tournament, come get \(winnerName).",
            scoreLine: nil,
            tier: nil
        )
    }

    public static func comeback(winnerName: String, headline: String, scoreLine: String) -> ShareCardContent {
        ShareCardContent(
            kind: .comeback,
            title: "Comeback",
            subtitle: headline,
            callToAction: "Think you can close it out against \(winnerName)?",
            scoreLine: scoreLine,
            tier: nil
        )
    }

    /// The card to offer after a confirmed match, if any. A belt changing
    /// hands beats an art upgrade, which beats a comeback.
    public static func prompt(
        for me: PlayerID,
        result: MatchResult,
        beltEvents: [BeltEvent],
        drama: DramaReport?
    ) -> ShareCardContent? {
        guard let myTeam = result.lineup.team(of: me), result.winner == myTeam else { return nil }
        let myName = result.lineup.name(of: myTeam, separator: " & ")

        let mine = beltEvents.filter { $0.holder.contains(me) && $0.isShareWorthy }
        if let won = mine.first(where: { if case .changedHands = $0 { return true } else { return false } }) {
            return beltWon(holderName: myName, sport: won.key.sport, scoreLine: result.perspective(of: me)?.scoreLine ?? result.scoreLine)
        }
        if case .defended(let key, _, let defenses, _)? = mine.first {
            return beltDefended(holderName: myName, sport: key.sport, defenses: defenses, tier: BeltTier(defenses: defenses))
        }
        if let drama, drama.isBigComeback {
            return comeback(winnerName: myName, headline: drama.headline(result.lineup), scoreLine: result.perspective(of: me)?.scoreLine ?? result.scoreLine)
        }
        return nil
    }
}
