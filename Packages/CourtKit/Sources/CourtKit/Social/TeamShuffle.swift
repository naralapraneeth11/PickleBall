//
//  TeamShuffle.swift
//  CourtKit
//
//  "Shuffle teams" for doubles when entering a score or starting a match:
//  a random split of four players that avoids repeating the last pairing.
//

import Foundation

public enum TeamShuffle {
    /// The three ways to split four players into two pairs.
    public static func pairings(of players: [PlayerRef]) -> [Lineup] {
        guard players.count == 4 else { return [] }
        let p = players
        return [
            Lineup(teamA: [p[0], p[1]], teamB: [p[2], p[3]]),
            Lineup(teamA: [p[0], p[2]], teamB: [p[1], p[3]]),
            Lineup(teamA: [p[0], p[3]], teamB: [p[1], p[2]])
        ]
    }

    /// A random lineup. With four players it never repeats `previous`'s
    /// partnerships; with two it just picks sides.
    public static func shuffle<R: RandomNumberGenerator>(
        _ players: [PlayerRef],
        avoiding previous: Lineup? = nil,
        using rng: inout R
    ) -> Lineup? {
        switch players.count {
        case 2:
            let sides = players.shuffled(using: &rng)
            return Lineup(teamA: [sides[0]], teamB: [sides[1]])
        case 4:
            var options = pairings(of: players)
            if let previous {
                let before = partnerships(previous)
                let fresh = options.filter { partnerships($0) != before }
                if !fresh.isEmpty { options = fresh }
            }
            guard var pick = options.randomElement(using: &rng) else { return nil }
            if Bool.random(using: &rng) { pick = Lineup(teams: pick.teams.swapped) }
            return pick
        default:
            return nil
        }
    }

    public static func shuffle(_ players: [PlayerRef], avoiding previous: Lineup? = nil) -> Lineup? {
        var rng = SystemRandomNumberGenerator()
        return shuffle(players, avoiding: previous, using: &rng)
    }

    static func partnerships(_ lineup: Lineup) -> Set<Set<PlayerID>> {
        [Set(lineup.teams.a.map(\.id)), Set(lineup.teams.b.map(\.id))]
    }
}
