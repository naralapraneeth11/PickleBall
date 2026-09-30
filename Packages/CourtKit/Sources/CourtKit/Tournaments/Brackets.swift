//
//  Brackets.swift
//  CourtKit
//
//  Knockout formats, all progressive: fixtures are added as the matches
//  that feed them finish, so the server only ever holds real pairings.
//
//  • Knockout (single elimination) — seeded, top seeds get the byes,
//    1 v 8, 4 v 5, 2 v 7, 3 v 6 so the top two can only meet in the final.
//  • Double elimination — a first loss drops you to the losers' bracket, a
//    second knocks you out. Winners' champion meets losers' champion in the
//    final; if the losers' champion wins, a reset match decides it.
//  • Pools + knockout — snake-seeded round-robin pools, then the top of
//    each pool plays a knockout, pool winners seeded first.
//  • Mexicano (padel) — Americano scoring, but each round groups players by
//    the standings (1st & 4th v 2nd & 3rd), so games stay close.
//
//  Every function is pure: give it the entrants in seed order, the
//  fixtures so far and their scores, and it says what's next. Every phone
//  in the squad works out the same bracket.
//

import Foundation

// MARK: - Bracket

public enum Bracket {
    /// Who fills one side of a bracket match.
    public enum Occupant: Hashable, Sendable {
        case entrant([PlayerID])
        /// Nobody: the other side goes through.
        case bye
        /// Decided by a match that hasn't finished.
        case pending

        public var entrant: [PlayerID]? {
            if case .entrant(let e) = self { return e }
            return nil
        }
    }

    /// A match in the bracket, played or not.
    public struct Node: Hashable, Sendable, Identifiable {
        public let stage: FixtureStage
        /// 1-based within its stage.
        public let round: Int
        /// 0-based within its round.
        public let slot: Int
        public let a: Occupant
        public let b: Occupant
        /// The fixture once it exists.
        public let fixture: Fixture?
        public let winner: Occupant
        public let loser: Occupant

        public var id: String { "\(stage.rawValue)-\(round)-\(slot)" }
        /// Both sides known, nothing recorded yet.
        public var isReady: Bool { a.entrant != nil && b.entrant != nil && winner == .pending }
        public var isDecided: Bool { winner != .pending }
        /// A bye: decided without a match.
        public var isWalkover: Bool { a == .bye || b == .bye }
    }

    /// How a round is named.
    public enum RoundName: Hashable, Sendable {
        case roundOf(Int)
        case quarterfinal
        case semifinal
        case final
        case winnersFinal
        case losers(round: Int)
        case losersFinal
        case grandFinal
        case reset
    }

    public struct State: Hashable, Sendable {
        public let size: Int
        public let isDouble: Bool
        public let nodes: [Node]
        /// Set once the last match is decided.
        public let champion: [PlayerID]?
        /// Runner-up once the champion is known.
        public let runnerUp: [PlayerID]?

        /// Winners' rounds (the only rounds in a knockout).
        public var winnersRounds: Int { size.trailingZeroBitCount }
        public var losersRounds: Int { isDouble ? 2 * (winnersRounds - 1) : 0 }

        public func nodes(_ stage: FixtureStage, round: Int) -> [Node] {
            nodes.filter { $0.stage == stage && $0.round == round }.sorted { $0.slot < $1.slot }
        }

        /// Matches whose players are known but that have no fixture yet:
        /// create these now.
        public var fixturesToAdd: [Fixture] {
            let ready = nodes.filter { $0.isReady && $0.fixture == nil }
            return ready.enumerated().map { i, node in
                Fixture(round: node.round, court: i + 1,
                        teams: TeamPair(a: node.a.entrant ?? [], b: node.b.entrant ?? []),
                        stage: node.stage, slot: node.slot)
            }
        }

        /// Matches waiting to be played, in bracket order.
        public var upcoming: [Node] { nodes.filter { $0.isReady } }

        public func name(of node: Node) -> RoundName {
            switch node.stage {
            case .losers:
                return node.round == losersRounds ? .losersFinal : .losers(round: node.round)
            case .final:
                return .grandFinal
            case .reset:
                return .reset
            default:
                let fromEnd = winnersRounds - node.round
                switch fromEnd {
                case 0: return isDouble ? .winnersFinal : .final
                case 1: return .semifinal
                case 2: return .quarterfinal
                default: return .roundOf(size >> (node.round - 1))
                }
            }
        }
    }

    /// Smallest power of two that fits everyone.
    public static func size(for entrants: Int) -> Int {
        var size = 2
        while size < entrants { size *= 2 }
        return size
    }

    /// Seed index at each bracket position: [0, 7, 3, 4, 1, 6, 2, 5] for 8,
    /// so the first round is 1 v 8, 4 v 5, 2 v 7, 3 v 6.
    public static func seedOrder(size: Int) -> [Int] {
        var order = [0]
        var width = 1
        while width < size {
            width *= 2
            order = order.flatMap { [$0, width - 1 - $0] }
        }
        return order
    }

    /// Works out the bracket from what's been played.
    ///
    /// - Parameters:
    ///   - entrants: players or fixed pairs, best seed first.
    ///   - double: double elimination (needs 3 or more entrants).
    ///   - fixtures: this bracket's fixtures (stages winners, losers, final
    ///     and reset; pool fixtures are ignored).
    public static func resolve(
        entrants: [[PlayerID]],
        double: Bool,
        fixtures: [Fixture],
        scores: [UUID: FixtureScore]
    ) -> State {
        let size = size(for: max(entrants.count, 2))
        let isDouble = double && entrants.count >= 3
        let rounds = size.trailingZeroBitCount
        var byKey: [String: Fixture] = [:]
        for fixture in fixtures where fixture.stage != .pool && fixture.stage != .main {
            if let slot = fixture.slot { byKey["\(fixture.stage.rawValue)-\(fixture.round)-\(slot)"] = fixture }
        }

        var nodes: [Node] = []
        func settle(_ stage: FixtureStage, _ round: Int, _ slot: Int, _ a: Occupant, _ b: Occupant) -> Node {
            let fixture = byKey["\(stage.rawValue)-\(round)-\(slot)"]
            var winner = Occupant.pending, loser = Occupant.pending
            if a == .bye {
                winner = b
                loser = .bye
            } else if b == .bye {
                winner = a
                loser = .bye
            } else if a.entrant != nil, b.entrant != nil, let fixture, let w = scores[fixture.id]?.winner {
                winner = .entrant(fixture.teams[w])
                loser = .entrant(fixture.teams[w.opponent])
            }
            let node = Node(stage: stage, round: round, slot: slot, a: a, b: b, fixture: fixture, winner: winner, loser: loser)
            nodes.append(node)
            return node
        }

        // Winners' bracket.
        let order = seedOrder(size: size)
        func seed(_ position: Int) -> Occupant {
            let s = order[position]
            return s < entrants.count ? .entrant(entrants[s]) : .bye
        }
        var winners: [[Node]] = [[]]  // 1-based
        for round in 1...rounds {
            let count = size >> round
            winners.append((0..<count).map { i in
                round == 1
                    ? settle(.winners, 1, i, seed(2 * i), seed(2 * i + 1))
                    : settle(.winners, round, i, winners[round - 1][2 * i].winner, winners[round - 1][2 * i + 1].winner)
            })
        }
        let winnersChampion = winners[rounds][0]

        guard isDouble else {
            let champion = winnersChampion.winner.entrant
            return State(size: size, isDouble: false, nodes: nodes, champion: champion,
                         runnerUp: champion == nil ? nil : winnersChampion.loser.entrant)
        }

        // Losers' bracket: odd rounds pair up the survivors, even rounds
        // bring in the next winners' round's losers (in reverse every other
        // time so people who just met don't meet again straight away).
        var losers: [[Node]] = [[]]
        let losersRounds = 2 * (rounds - 1)
        for round in 1...losersRounds {
            let k = round / 2
            if round == 1 {
                losers.append((0..<(size / 4)).map { i in
                    settle(.losers, 1, i, winners[1][2 * i].loser, winners[1][2 * i + 1].loser)
                })
            } else if round.isMultiple(of: 2) {
                let count = size >> (k + 1)
                losers.append((0..<count).map { i in
                    let j = k.isMultiple(of: 2) ? i : count - 1 - i
                    return settle(.losers, round, i, losers[round - 1][i].winner, winners[k + 1][j].loser)
                })
            } else {
                let count = size >> (k + 2)
                losers.append((0..<count).map { i in
                    settle(.losers, round, i, losers[round - 1][2 * i].winner, losers[round - 1][2 * i + 1].winner)
                })
            }
        }
        let losersChampion = losers[losersRounds][0]

        let final = settle(.final, 1, 0, winnersChampion.winner, losersChampion.winner)
        var champion: [PlayerID]?
        var runnerUp: [PlayerID]?
        if let winner = final.winner.entrant {
            if final.a.entrant == winner || final.b == .bye {
                champion = winner
                runnerUp = final.loser.entrant
            } else {
                // The losers' champion handed the winners' champion their
                // first loss: one more match.
                let reset = settle(.reset, 1, 0, final.a, final.b)
                champion = reset.winner.entrant
                runnerUp = reset.loser.entrant
            }
        }
        return State(size: size, isDouble: true, nodes: nodes, champion: champion, runnerUp: runnerUp)
    }
}

// MARK: - Pools

public enum Pools {
    /// Pools of about four.
    public static func suggestedCount(entrants: Int) -> Int {
        max(1, Int((Double(entrants) / 4).rounded()))
    }

    /// How many from each pool go through: enough for a bracket of 4 or 8.
    public static func suggestedAdvancing(entrants: Int, pools: Int) -> Int {
        guard pools > 0 else { return 0 }
        let target = entrants >= 12 ? 8 : 4
        return max(1, min(target / pools, entrants / pools))
    }

    /// Snake seeding: 1 2 3 4 / 8 7 6 5 / 9 10 11 12…
    public static func split(_ entrants: [[PlayerID]], pools count: Int) -> [[[PlayerID]]] {
        let count = max(1, min(count, entrants.count / 2 == 0 ? 1 : entrants.count / 2))
        var pools = [[[PlayerID]]](repeating: [], count: count)
        for (i, entrant) in entrants.enumerated() {
            let pass = i / count, offset = i % count
            pools[pass.isMultiple(of: 2) ? offset : count - 1 - offset].append(entrant)
        }
        return pools
    }

    /// A round robin in every pool. Pools play their rounds side by side
    /// on separate courts.
    public static func schedule(_ pools: [[[PlayerID]]]) -> [Fixture] {
        var fixtures: [Fixture] = []
        var courtsUsed: [Int: Int] = [:]
        for (index, pool) in pools.enumerated() {
            for fixture in RoundRobin.schedule(pool) {
                let court = courtsUsed[fixture.round, default: 0] + 1
                courtsUsed[fixture.round] = court
                fixtures.append(Fixture(round: fixture.round, court: court, teams: fixture.teams, stage: .pool, pool: index))
            }
        }
        return fixtures
    }

    public static func standings(pools: [[[PlayerID]]], fixtures: [Fixture], scores: [UUID: FixtureScore]) -> [[StandingRow]] {
        pools.enumerated().map { index, pool in
            Standings.compute(format: .roundRobin, entrants: pool,
                              fixtures: fixtures.filter { $0.stage == .pool && $0.pool == index }, scores: scores)
        }
    }

    /// Seeds for the knockout once every pool match has a result: all pool
    /// winners (best record first), then all runners-up, and so on.
    public static func qualifiers(
        pools: [[[PlayerID]]],
        advancing: Int,
        fixtures: [Fixture],
        scores: [UUID: FixtureScore]
    ) -> [[PlayerID]]? {
        let poolFixtures = fixtures.filter { $0.stage == .pool }
        guard !poolFixtures.isEmpty, poolFixtures.allSatisfy({ scores[$0.id]?.winner != nil }) else { return nil }
        let tables = standings(pools: pools, fixtures: fixtures, scores: scores)
        var seeds: [[PlayerID]] = []
        for place in 0..<advancing {
            let tier = tables.compactMap { $0.indices.contains(place) ? $0[place] : nil }
                .sorted { x, y in
                    let xr = Double(x.wins) / Double(max(x.played, 1)), yr = Double(y.wins) / Double(max(y.played, 1))
                    if xr != yr { return xr > yr }
                    if x.pointDifference != y.pointDifference { return x.pointDifference > y.pointDifference }
                    if x.pointsFor != y.pointsFor { return x.pointsFor > y.pointsFor }
                    return x.id < y.id
                }
            seeds += tier.map(\.entrant)
        }
        return avoidingPoolRematches(seeds, pools: pools, perTier: tables.filter { !$0.isEmpty }.count)
    }

    /// Swaps seeds within a tier (all winners, all runners-up…) so nobody
    /// meets someone from their own pool in the first knockout round.
    static func avoidingPoolRematches(_ seeds: [[PlayerID]], pools: [[[PlayerID]]], perTier: Int) -> [[PlayerID]] {
        guard perTier > 1 else { return seeds }
        var seeds = seeds
        let poolOf = { (e: [PlayerID]) in pools.firstIndex { $0.contains(e) } }
        let order = Bracket.seedOrder(size: Bracket.size(for: seeds.count))
        func opponent(_ s: Int) -> Int? {
            guard let position = order.firstIndex(of: s) else { return nil }
            let other = order[position ^ 1]
            return other < seeds.count ? other : nil
        }
        func clashes(_ s: Int) -> Bool {
            guard let o = opponent(s) else { return false }
            return poolOf(seeds[s]) == poolOf(seeds[o])
        }
        for s in seeds.indices where clashes(s) {
            let t = max(s, opponent(s)!)
            let tier = t / perTier
            for u in (tier * perTier)..<min((tier + 1) * perTier, seeds.count) where u != t {
                seeds.swapAt(t, u)
                if !clashes(t) && !clashes(u) { break }
                seeds.swapAt(t, u)
            }
        }
        return seeds
    }
}

// MARK: - Mexicano

public enum Mexicano {
    /// Round 1 pairs players in the order given (a rough seeding).
    public static func firstRound(_ players: [PlayerID], courts: Int? = nil) -> [Fixture] {
        round(1, ranked: players, games: [:], courts: courts)
    }

    /// The next round from the standings, or nil until the last round is
    /// fully scored.
    public static func nextRound(
        players: [PlayerID],
        fixtures: [Fixture],
        scores: [UUID: FixtureScore],
        courts: Int? = nil
    ) -> [Fixture]? {
        guard let last = fixtures.map(\.round).max() else { return firstRound(players, courts: courts) }
        guard fixtures.filter({ $0.round == last }).allSatisfy({ scores[$0.id] != nil }) else { return nil }
        var games: [PlayerID: Int] = [:]
        for fixture in fixtures { for p in fixture.players { games[p, default: 0] += 1 } }
        return round(last + 1, ranked: ranking(players: players, fixtures: fixtures, scores: scores), games: games, courts: courts)
    }

    /// Points won, then wins, then point difference, then seed.
    public static func ranking(players: [PlayerID], fixtures: [Fixture], scores: [UUID: FixtureScore]) -> [PlayerID] {
        let rows = Standings.compute(format: .mexicano, entrants: players.map { [$0] }, fixtures: fixtures, scores: scores)
        let byPlayer = Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.entrant.first.map { ($0, row) } })
        let seed = Dictionary(uniqueKeysWithValues: players.enumerated().map { ($1, $0) })
        return players.sorted { x, y in
            let rx = byPlayer[x], ry = byPlayer[y]
            let kx = (rx?.pointsFor ?? 0, rx?.wins ?? 0, rx?.pointDifference ?? 0)
            let ky = (ry?.pointsFor ?? 0, ry?.wins ?? 0, ry?.pointDifference ?? 0)
            if kx != ky { return kx > ky }
            return seed[x]! < seed[y]!
        }
    }

    static func round(_ number: Int, ranked: [PlayerID], games: [PlayerID: Int], courts: Int?) -> [Fixture] {
        let n = ranked.count
        guard n >= 4 else { return [] }
        let courtCount = max(1, min(courts ?? n / 4, n / 4))
        // Whoever has played least plays; among equals, the lowest ranked sit.
        let position = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, $0) })
        let playing = Set(ranked.sorted {
            (games[$0, default: 0], position[$0]!) < (games[$1, default: 0], position[$1]!)
        }.prefix(courtCount * 4))
        let order = ranked.filter { playing.contains($0) }
        return (0..<courtCount).map { c in
            let g = Array(order[(c * 4)..<(c * 4 + 4)])
            return Fixture(round: number, court: c + 1, teams: TeamPair(a: [g[0], g[3]], b: [g[1], g[2]]))
        }
    }
}
