//
//  SquadTournament.swift
//  CourtKit
//
//  Squad tournaments. League formats live here; brackets, pools and
//  Mexicano are in Brackets.swift.
//
//  • Round robin — every entrant (player or fixed pair) plays every other
//    once. Standings: wins, then head-to-head between two tied entrants,
//    then point difference, then points scored.
//  • King of the Court — courts are ranked, court 1 is the king court.
//    Winners move up a court, losers move down, and partners split every
//    round so everyone plays with everyone. Standings: wins, then wins on
//    the king court, then point difference.
//  • Americano (padel) — partners rotate so each player partners every
//    other player once; every point you win counts for you. Standings:
//    total points, then wins, then point difference.
//
//  Fixtures carry player IDs only. Anyone in the squad can score any match.
//

import Foundation

public enum TournamentFormat: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case roundRobin = "round_robin"
    case kingOfTheCourt = "king_of_court"
    case americano
    case mexicano
    case singleElimination = "single_elimination"
    case doubleElimination = "double_elimination"
    case pools

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .roundRobin: return "Round robin"
        case .kingOfTheCourt: return "King of the Court"
        case .americano: return "Americano"
        case .mexicano: return "Mexicano"
        case .singleElimination: return "Knockout"
        case .doubleElimination: return "Double elimination"
        case .pools: return "Pools + knockout"
        }
    }

    public var blurb: String {
        switch self {
        case .roundRobin: return "Everyone plays everyone once."
        case .kingOfTheCourt: return "Win and move up. Lose and move down. Partners change every round."
        case .americano: return "New partner every round. Every point you win counts."
        case .mexicano: return "Like Americano, but each round pairs players by the standings: close games all night."
        case .singleElimination: return "Lose once and you're out. Top seeds get the byes."
        case .doubleElimination: return "Lose twice and you're out. The losers' bracket gets a second life."
        case .pools: return "Round robin in small pools, then the top of each pool plays a knockout."
        }
    }

    /// Fixtures are added as earlier ones finish.
    public var isProgressive: Bool {
        switch self {
        case .roundRobin, .americano: return false
        default: return true
        }
    }

    public var isBracket: Bool { self == .singleElimination || self == .doubleElimination }

    /// Rotating-partner formats rank players; the rest rank entrants as
    /// entered (players or fixed pairs).
    public var ranksIndividuals: Bool { self == .kingOfTheCourt || self == .americano || self == .mexicano }

    /// Points won decide the standings.
    public var ranksByPoints: Bool { self == .americano || self == .mexicano }

    /// Formats that make sense for a sport.
    public static func available(for sport: Sport) -> [TournamentFormat] {
        sport == .padel
            ? [.americano, .mexicano, .roundRobin, .singleElimination, .doubleElimination, .pools, .kingOfTheCourt]
            : [.roundRobin, .singleElimination, .doubleElimination, .pools, .kingOfTheCourt]
    }
}

/// Where a fixture sits in a tournament.
public enum FixtureStage: String, Codable, Hashable, Sendable {
    /// League play: round robin, King of the Court, Americano, Mexicano.
    case main
    case pool
    /// The (only) bracket in a knockout, or the winners' side of a double.
    case winners
    case losers
    /// Double elimination: winners' champion against losers' champion.
    case final
    /// Double elimination: played only if the losers' champion wins the final.
    case reset
}

public struct Fixture: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// 1-based.
    public var round: Int
    /// 1-based. In King of the Court, court 1 is the king court.
    public var court: Int
    public var teams: TeamPair<[PlayerID]>
    public var scheduledAt: Date?
    public var place: CourtTag?
    public var stage: FixtureStage
    /// Position within a bracket round (0-based).
    public var slot: Int?
    /// Pool index (0-based) in pool play.
    public var pool: Int?

    public init(id: UUID = UUID(), round: Int, court: Int, teams: TeamPair<[PlayerID]>, scheduledAt: Date? = nil, place: CourtTag? = nil,
                stage: FixtureStage = .main, slot: Int? = nil, pool: Int? = nil) {
        self.id = id
        self.round = round
        self.court = court
        self.teams = teams
        self.scheduledAt = scheduledAt
        self.place = place
        self.stage = stage
        self.slot = slot
        self.pool = pool
    }

    public var players: [PlayerID] { teams.a + teams.b }

    private enum CodingKeys: String, CodingKey { case id, round, court, teams, scheduledAt, place, stage, slot, pool }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  round: try c.decode(Int.self, forKey: .round),
                  court: try c.decode(Int.self, forKey: .court),
                  teams: try c.decode(TeamPair<[PlayerID]>.self, forKey: .teams),
                  scheduledAt: try c.decodeIfPresent(Date.self, forKey: .scheduledAt),
                  place: try c.decodeIfPresent(CourtTag.self, forKey: .place),
                  // Cached before Phase 3: league fixtures.
                  stage: try c.decodeIfPresent(FixtureStage.self, forKey: .stage) ?? .main,
                  slot: try c.decodeIfPresent(Int.self, forKey: .slot),
                  pool: try c.decodeIfPresent(Int.self, forKey: .pool))
    }
}

/// A played fixture: points (or games) per side.
public struct FixtureScore: Hashable, Codable, Sendable {
    public var score: TeamPair<Int>
    public var winner: Team?

    public init(score: TeamPair<Int>, winner: Team? = nil) {
        self.score = score
        self.winner = winner ?? score.leader
    }
}

// MARK: - Round robin

public enum RoundRobin {
    /// Circle-method schedule. `entrants` are players (singles) or fixed
    /// pairs. With an odd count one entrant sits out each round.
    public static func schedule(_ entrants: [[PlayerID]], courts: Int = .max) -> [Fixture] {
        guard entrants.count >= 2 else { return [] }
        let rounds = circleRounds(entrants.count)
        var fixtures: [Fixture] = []
        for (r, pairs) in rounds.enumerated() {
            var court = 0
            for (i, j) in pairs {
                // Alternate sides so nobody is always "team A".
                let (x, y) = (r + court).isMultiple(of: 2) ? (i, j) : (j, i)
                fixtures.append(Fixture(round: r + 1, court: court % max(courts, 1) + 1,
                                        teams: TeamPair(a: entrants[x], b: entrants[y])))
                court += 1
            }
        }
        return fixtures
    }

    /// Rounds of index pairs where everyone meets everyone once. Byes (the
    /// phantom entrant in an odd field) are left out.
    static func circleRounds(_ count: Int) -> [[(Int, Int)]] {
        let n = count.isMultiple(of: 2) ? count : count + 1
        var ring = Array(0..<n)
        var rounds: [[(Int, Int)]] = []
        for _ in 0..<(n - 1) {
            var pairs: [(Int, Int)] = []
            for k in 0..<(n / 2) {
                let a = ring[k], b = ring[n - 1 - k]
                if a < count && b < count { pairs.append((a, b)) }
            }
            rounds.append(pairs)
            // Keep the first seat fixed, rotate the rest.
            ring = [ring[0], ring[n - 1]] + ring[1..<(n - 1)]
        }
        return rounds
    }
}

// MARK: - King of the Court

public enum KingOfTheCourt {
    /// Players per court.
    public static func courtSize(doubles: Bool) -> Int { doubles ? 4 : 2 }

    /// First round: players fill courts in the order given (seed order), the
    /// rest wait on the bench and rotate in at the bottom court.
    public static func firstRound(_ players: [PlayerID], doubles: Bool) -> (fixtures: [Fixture], bench: [PlayerID]) {
        let size = courtSize(doubles: doubles)
        let courts = players.count / size
        var fixtures: [Fixture] = []
        for c in 0..<courts {
            let group = Array(players[(c * size)..<((c + 1) * size)])
            let teams = doubles
                ? TeamPair(a: [group[0], group[3]], b: [group[1], group[2]])
                : TeamPair(a: [group[0]], b: [group[1]])
            fixtures.append(Fixture(round: 1, court: c + 1, teams: teams))
        }
        return (fixtures, Array(players[(courts * size)...]))
    }

    /// The next round from the last one's results. Returns nil until every
    /// court in the round has a winner.
    public static func nextRound(
        after round: [Fixture],
        scores: [UUID: FixtureScore],
        bench: [PlayerID],
        doubles: Bool
    ) -> (fixtures: [Fixture], bench: [PlayerID])? {
        let courts = round.sorted { $0.court < $1.court }
        guard let number = courts.first?.round, !courts.isEmpty else { return nil }
        var winners: [[PlayerID]] = []
        var losers: [[PlayerID]] = []
        for fixture in courts {
            guard let winner = scores[fixture.id]?.winner else { return nil }
            winners.append(fixture.teams[winner])
            losers.append(fixture.teams[winner.opponent])
        }

        // Bottom-court losers make way for whoever has waited longest.
        var bench = bench
        var bottomLosers = losers[courts.count - 1]
        if !bench.isEmpty {
            let comingIn = Array(bench.prefix(bottomLosers.count))
            bench = Array(bench.dropFirst(comingIn.count)) + bottomLosers
            bottomLosers = comingIn + bottomLosers.dropFirst(comingIn.count)
        }

        // Each court gets the losers from the court above and the winners
        // from the court below. The king court keeps its winners; the bottom
        // court keeps its losers (or takes the bench).
        var fixtures: [Fixture] = []
        let last = courts.count - 1
        for c in 0...last {
            let above = c == 0 ? winners[0] : losers[c - 1]
            let below = c == last ? bottomLosers : winners[c + 1]
            let teams: TeamPair<[PlayerID]>
            if doubles, above.count == 2, below.count == 2 {
                // Partners split: each arriving pair is broken up.
                teams = TeamPair(a: [above[0], below[1]], b: [above[1], below[0]])
            } else {
                teams = TeamPair(a: above, b: below)
            }
            fixtures.append(Fixture(round: number + 1, court: c + 1, teams: teams))
        }
        return (fixtures, bench)
    }
}

// MARK: - Americano

public enum Americano {
    /// Rotating-partner schedule.
    ///
    /// When everyone fits on court at once (4, 8, 12… players), partners
    /// come from a round robin, so over n − 1 rounds everyone partners
    /// everyone exactly once. Otherwise each round the players with the
    /// fewest games play, partnered with whoever they've partnered least,
    /// and the default number of rounds is the smallest that gives everyone
    /// the same number of games. Either way pairs are matched to spread
    /// opponents evenly.
    public static func schedule(_ players: [PlayerID], courts: Int? = nil, rounds: Int? = nil) -> [Fixture] {
        let n = players.count
        guard n >= 4 else { return [] }
        let courtCount = max(1, min(courts ?? n / 4, n / 4))
        let perRound = courtCount * 4

        var tally = Tally()
        var fixtures: [Fixture] = []

        if perRound == n {
            let partnerRounds = RoundRobin.circleRounds(n)
            for r in 0..<(rounds ?? n - 1) {
                let pairs = partnerRounds[r % partnerRounds.count].map { [players[$0.0], players[$0.1]] }
                fixtures += tally.match(pairs, round: r + 1)
            }
            return fixtures
        }

        var games = [Int](repeating: 0, count: n)
        for r in 0..<(rounds ?? defaultRounds(players: n, perRound: perRound)) {
            // Fewest games first; ties rotate so the same people don't
            // always sit.
            let shift = (r * perRound) % n
            let chosen = players.indices
                .sorted { (games[$0], ($0 - shift + n) % n) < (games[$1], ($1 - shift + n) % n) }
                .prefix(perRound)
            for i in chosen { games[i] += 1 }

            var pool = chosen.map { players[$0] }
            var pairs: [[PlayerID]] = []
            while let p = pool.first {
                pool.removeFirst()
                let best = pool.indices.min { tally.partnerCost(p, pool[$0]) < tally.partnerCost(p, pool[$1]) } ?? 0
                let q = pool.remove(at: best)
                tally.partnered(p, q)
                pairs.append([p, q])
            }
            fixtures += tally.match(pairs, round: r + 1)
        }
        return fixtures
    }

    /// The smallest number of rounds, at least n − 1, after which everyone
    /// has played the same number of games.
    static func defaultRounds(players n: Int, perRound: Int) -> Int {
        let minimum = n - 1
        return (minimum...(minimum + n)).first { ($0 * perRound) % n == 0 } ?? minimum
    }

    struct Tally {
        var partners: [Set<PlayerID>: Int] = [:]
        var opponents: [Set<PlayerID>: Int] = [:]

        func partnerCost(_ p: PlayerID, _ q: PlayerID) -> (Int, Int) {
            (partners[Set([p, q]), default: 0], opponents[Set([p, q]), default: 0])
        }

        mutating func partnered(_ p: PlayerID, _ q: PlayerID) {
            partners[Set([p, q]), default: 0] += 1
        }

        /// Pairs each pair with the opponents it has met least.
        mutating func match(_ pairs: [[PlayerID]], round: Int) -> [Fixture] {
            var remaining = pairs
            var fixtures: [Fixture] = []
            while remaining.count >= 2 {
                let first = remaining.removeFirst()
                var bestIndex = 0
                var bestCost = Int.max
                for (i, other) in remaining.enumerated() {
                    var cost = 0
                    for p in first {
                        for q in other { cost += opponents[Set([p, q]), default: 0] }
                    }
                    if cost < bestCost {
                        bestCost = cost
                        bestIndex = i
                    }
                }
                let second = remaining.remove(at: bestIndex)
                for p in first {
                    for q in second { opponents[Set([p, q]), default: 0] += 1 }
                }
                fixtures.append(Fixture(round: round, court: fixtures.count + 1, teams: TeamPair(a: first, b: second)))
            }
            return fixtures
        }
    }
}

// MARK: - Standings

public struct StandingRow: Identifiable, Hashable, Sendable {
    /// A player, or a fixed pair in doubles round robin.
    public let entrant: [PlayerID]
    public internal(set) var played = 0
    public internal(set) var wins = 0
    public internal(set) var losses = 0
    public internal(set) var pointsFor = 0
    public internal(set) var pointsAgainst = 0
    /// King of the Court: wins on court 1.
    public internal(set) var kingCourtWins = 0
    /// 1-based; tied rows share a rank.
    public internal(set) var rank = 0

    public var id: String { entrant.map(\.rawValue.uuidString).joined(separator: "+") }
    public var pointDifference: Int { pointsFor - pointsAgainst }

    init(entrant: [PlayerID]) { self.entrant = entrant }
}

public enum Standings {
    public static func compute(
        format: TournamentFormat,
        entrants: [[PlayerID]],
        fixtures: [Fixture],
        scores: [UUID: FixtureScore]
    ) -> [StandingRow] {
        // Rotating-partner formats rank individuals; the others rank the
        // entrants as entered (players or fixed pairs).
        let individual = format.ranksIndividuals
        let units: [[PlayerID]] = individual ? Array(Set(entrants.flatMap { $0 })).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.map { [$0] } : entrants
        var rows: [String: StandingRow] = [:]
        for unit in units { rows[key(unit)] = StandingRow(entrant: unit) }
        var headToHead: [String: [String: Int]] = [:]  // winner → loser → wins

        for fixture in fixtures {
            guard let result = scores[fixture.id] else { continue }
            for team in Team.allCases {
                let members: [[PlayerID]] = individual ? fixture.teams[team].map { [$0] } : [fixture.teams[team]]
                for member in members {
                    let k = key(member)
                    guard var row = rows[k] else { continue }
                    row.played += 1
                    row.pointsFor += result.score[team]
                    row.pointsAgainst += result.score[team.opponent]
                    if result.winner == team {
                        row.wins += 1
                        if fixture.court == 1 { row.kingCourtWins += 1 }
                    } else if result.winner == team.opponent {
                        row.losses += 1
                    }
                    rows[k] = row
                }
            }
            if !individual, let winner = result.winner {
                headToHead[key(fixture.teams[winner]), default: [:]][key(fixture.teams[winner.opponent]), default: 0] += 1
            }
        }

        func beats(_ x: StandingRow, _ y: StandingRow) -> Int {
            headToHead[x.id]?[y.id] ?? 0
        }
        // Head-to-head only separates a two-way tie; with three or more it
        // can go in circles.
        let tiedOnWins = Dictionary(grouping: rows.values, by: \.wins).mapValues(\.count)

        func order(_ x: StandingRow, _ y: StandingRow) -> Bool? {
            switch format {
            case .roundRobin, .pools, .singleElimination, .doubleElimination:
                if x.wins != y.wins { return x.wins > y.wins }
                if tiedOnWins[x.wins] == 2 {
                    let hx = beats(x, y), hy = beats(y, x)
                    if hx != hy { return hx > hy }
                }
                if x.pointDifference != y.pointDifference { return x.pointDifference > y.pointDifference }
                if x.pointsFor != y.pointsFor { return x.pointsFor > y.pointsFor }
            case .kingOfTheCourt:
                if x.wins != y.wins { return x.wins > y.wins }
                if x.kingCourtWins != y.kingCourtWins { return x.kingCourtWins > y.kingCourtWins }
                if x.pointDifference != y.pointDifference { return x.pointDifference > y.pointDifference }
            case .americano, .mexicano:
                if x.pointsFor != y.pointsFor { return x.pointsFor > y.pointsFor }
                if x.wins != y.wins { return x.wins > y.wins }
                if x.pointDifference != y.pointDifference { return x.pointDifference > y.pointDifference }
            }
            return nil
        }

        var sorted = rows.values.sorted { x, y in order(x, y) ?? (x.id < y.id) }
        for i in sorted.indices {
            if i > 0, order(sorted[i - 1], sorted[i]) == nil {
                sorted[i].rank = sorted[i - 1].rank
            } else {
                sorted[i].rank = i + 1
            }
        }
        return sorted
    }

    /// Everyone sharing first place once every fixture has a result.
    public static func champions(_ rows: [StandingRow], fixtures: [Fixture], scores: [UUID: FixtureScore]) -> [PlayerID]? {
        guard !fixtures.isEmpty, fixtures.allSatisfy({ scores[$0.id]?.winner != nil }) else { return nil }
        return rows.filter { $0.rank == 1 }.flatMap(\.entrant)
    }

    static func key(_ entrant: [PlayerID]) -> String {
        entrant.map(\.rawValue.uuidString).joined(separator: "+")
    }
}
